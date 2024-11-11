//
//  DetailSearchReducer.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/12.
//

import ComposableArchitecture

@Reducer
struct DetailSearchReducer {
    @dynamicMemberLookup @CasePathable
    enum Route: Equatable {
        case filters(EquatableVoid = .unique)
        case quickSearch(EquatableVoid = .unique)
        case detail(String)
    }

    private enum CancelID: CaseIterable {
        case fetchGalleries, fetchMoreGalleries
    }

    @ObservableState
    struct State: Equatable {
        var route: Route?
        var keyword = ""
        var lastKeyword = ""

        var galleries = [Gallery]()
        var pageNumber = PageNumber()
        var loadingState: LoadingState = .idle
        var footerLoadingState: LoadingState = .idle

        var detailState: Heap<DetailReducer.State?>
        var filtersState = FiltersReducer.State()
        var quickDetailSearchState = QuickSearchReducer.State()

        init() {
            detailState = .init(.init())
        }

        mutating func insertGalleries(_ galleries: [Gallery]) {
            galleries.forEach { gallery in
                if !self.galleries.contains(gallery) {
                    self.galleries.append(gallery)
                }
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case setNavigation(Route?)
        case clearSubStates

        case teardown
        case fetchGalleries(String? = nil)
        case fetchGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)
        case fetchMoreGalleries
        case fetchMoreGalleriesDone(Result<(PageNumber, [Gallery]), AppError>)

        case detail(DetailReducer.Action)
        case filters(FiltersReducer.Action)
        case quickSearch(QuickSearchReducer.Action)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.hapticsClient) private var hapticsClient

    var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.route) { _, newValue in
                Reduce({ _, _ in newValue == nil ? .send(.clearSubStates) : .none })
            }
            .onChange(of: \.keyword) { _, newValue in
                Reduce { state, _ in
                    if !newValue.isEmpty {
                        state.lastKeyword = newValue
                    }
                    return .none
                }
            }

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .setNavigation(let route):
                state.route = route
                return route == nil ? .send(.clearSubStates) : .none

            case .clearSubStates:
                state.detailState.wrappedValue = .init()
                state.filtersState = .init()
                state.quickDetailSearchState = .init()
                return .merge(
                    .send(.detail(.teardown)),
                    .send(.quickSearch(.teardown))
                )

            case .teardown:
                return .merge(CancelID.allCases.map(Effect.cancel(id:)))

            case .fetchGalleries(let keyword):
                guard state.loadingState != .loading else { return .none }
                if let keyword = keyword {
                    state.keyword = keyword
                    state.lastKeyword = keyword
                }
                state.loadingState = .loading
                state.pageNumber.resetPages()
                let filter = databaseClient.fetchFilterSynchronously(range: .search)
                return .run { [lastKeyword = state.lastKeyword] send in
                    let response = await SearchGalleriesRequest(keyword: lastKeyword, filter: filter).response()
                    await send(.fetchGalleriesDone(response))
                }
                .cancellable(id: CancelID.fetchGalleries)

            case .fetchGalleriesDone(let result):
                state.loadingState = .idle
                switch result {
                case .success(let (pageNumber, galleries)):
                    guard !galleries.isEmpty else {
                        state.loadingState = .failed(.notFound)
                        guard pageNumber.hasNextPage() else { return .none }
                        return .send(.fetchMoreGalleries)
                    }
                    state.pageNumber = pageNumber
                    state.galleries = galleries
                    return .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                case .failure(let error):
                    state.loadingState = .failed(error)
                }
                return .none

            case .fetchMoreGalleries:
                let pageNumber = state.pageNumber
                guard pageNumber.hasNextPage(),
                      state.footerLoadingState != .loading,
                      let lastID = state.galleries.last?.id
                else { return .none }
                state.footerLoadingState = .loading
                let filter = databaseClient.fetchFilterSynchronously(range: .search)
                return .run { [lastKeyword = state.lastKeyword] send in
                    let response = await MoreSearchGalleriesRequest(
                        keyword: lastKeyword, filter: filter, lastID: lastID
                    )
                    .response()
                    await send(.fetchMoreGalleriesDone(response))
                }
                .cancellable(id: CancelID.fetchMoreGalleries)

            case .fetchMoreGalleriesDone(let result):
                state.footerLoadingState = .idle
                switch result {
                case .success(let (pageNumber, galleries)):
                    state.pageNumber = pageNumber
                    state.insertGalleries(galleries)

                    var effects: [Effect<Action>] = [
                        .run(operation: { _ in await databaseClient.cacheGalleries(galleries) })
                    ]
                    if galleries.isEmpty, pageNumber.hasNextPage() {
                        effects.append(.send(.fetchMoreGalleries))
                    } else if !galleries.isEmpty {
                        state.loadingState = .idle
                    }
                    return .merge(effects)

                case .failure(let error):
                    state.footerLoadingState = .failed(error)
                }
                return .none

            case .detail:
                return .none

            case .filters:
                return .none

            case .quickSearch:
                return .none
            }
        }
        .haptics(
            unwrapping: \.route,
            case: \.quickSearch,
            hapticsClient: hapticsClient
        )
        .haptics(
            unwrapping: \.route,
            case: \.filters,
            hapticsClient: hapticsClient
        )

        Scope(state: \.filtersState, action: \.filters, child: FiltersReducer.init)
        Scope(state: \.quickDetailSearchState, action: \.quickSearch, child: QuickSearchReducer.init)
    }
}
