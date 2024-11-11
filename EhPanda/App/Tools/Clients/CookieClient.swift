//
//  CookieClient.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 4/01/02.
//

import Foundation
import ComposableArchitecture

struct CookieClient {
    let clearAll: () -> Void
    let getCookie: (URL, String) -> CookieValue
    private let removeCookie: (URL, String) -> Void
    private let checkExistence: (URL, String) -> Bool
    private let initializeCookie: (HTTPCookie, String) -> HTTPCookie
}

extension CookieClient {
    static let live: Self = .init(
        clearAll: {
            if let historyCookies = HTTPCookieStorage.shared.cookies {
                historyCookies.forEach {
                    HTTPCookieStorage.shared.deleteCookie($0)
                }
            }
        },
        getCookie: { url, key in
            var value = CookieValue(
                rawValue: "", localizedString: L10n.Localizable.Struct.CookieValue.LocalizedString.none
            )
            guard let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty else { return value }

            cookies.forEach { cookie in
                guard let expiresDate = cookie.expiresDate, cookie.name == key && !cookie.value.isEmpty else { return }
                guard expiresDate > .now else {
                    value = CookieValue(
                        rawValue: "", localizedString: L10n.Localizable.Struct.CookieValue.LocalizedString.expired
                    )
                    return
                }
                guard cookie.value != Defaults.Cookie.mystery else {
                    value = CookieValue(
                        rawValue: cookie.value, localizedString:
                            L10n.Localizable.Struct.CookieValue.LocalizedString.mystery
                    )
                    return
                }
                value = CookieValue(rawValue: cookie.value, localizedString: "")
            }

            return value
        },
        removeCookie: { url, key in
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                cookies.forEach { cookie in
                    guard cookie.name == key else { return }
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        },
        checkExistence: { url, key in
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                var existence: HTTPCookie?
                cookies.forEach { cookie in
                    guard cookie.name == key else { return }
                    existence = cookie
                }
                return existence != nil
            } else {
                return false
            }
        },
        initializeCookie: { cookie, value in
            var properties = cookie.properties
            properties?[.value] = value
            return HTTPCookie(properties: properties ?? [:]) ?? HTTPCookie()
        }
    )
}

// MARK: Foundation
extension CookieClient {
    private func setCookie(
        for url: URL, key: String, value: String, path: String = "/",
        expiresTime: TimeInterval = .oneYear
    ) {
        let expiredDate = Date(timeIntervalSinceNow: expiresTime)
        let properties: [HTTPCookiePropertyKey: Any] = [
            .path: path, .name: key, .value: value,
            .originURL: url, .expires: expiredDate
        ]
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
    func editCookie(for url: URL, key: String, value: String) {
        var newCookie: HTTPCookie?
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            cookies.forEach { cookie in
                guard cookie.name == key else { return }
                newCookie = initializeCookie(cookie, value)
                removeCookie(url, key)
            }
        }
        guard let cookie = newCookie else { return }
        HTTPCookieStorage.shared.setCookie(cookie)
    }
    func setOrEditCookie(for url: URL, key: String, value: String) {
        if checkExistence(url, key) {
            editCookie(for: url, key: key, value: value)
        } else {
            setCookie(for: url, key: key, value: value)
        }
    }
}

// MARK: Accessor
extension CookieClient {
    var didLogin: Bool {
        CookieUtil.didLogin
    }
    var apiuid: String {
        getCookie(Defaults.URL.host, Defaults.Cookie.ipbMemberId).rawValue
    }
    var isSameAccount: Bool {
        let ehUID = getCookie(Defaults.URL.ehentai, Defaults.Cookie.ipbMemberId).rawValue
        let exUID = getCookie(Defaults.URL.exhentai, Defaults.Cookie.ipbMemberId).rawValue
        if !ehUID.isEmpty && !exUID.isEmpty { return ehUID == exUID } else { return false }
    }
    var shouldFetchIgneous: Bool {
        let url = Defaults.URL.exhentai
        return !getCookie(url, Defaults.Cookie.ipbMemberId).rawValue.isEmpty
        && !getCookie(url, Defaults.Cookie.ipbPassHash).rawValue.isEmpty
        && getCookie(url, Defaults.Cookie.igneous).rawValue.isEmpty
    }
    func removeYay() {
        removeCookie(Defaults.URL.exhentai, Defaults.Cookie.yay)
        removeCookie(Defaults.URL.sexhentai, Defaults.Cookie.yay)
    }
    func syncExCookies() {
        let cookies = [
            Defaults.Cookie.ipbMemberId,
            Defaults.Cookie.ipbPassHash,
            Defaults.Cookie.igneous
        ]
        for cookie in cookies {
            setOrEditCookie(
                for: Defaults.URL.sexhentai,
                key: cookie,
                value: getCookie(Defaults.URL.exhentai, cookie).rawValue
            )
        }
    }
    func ignoreOffensive() {
        setOrEditCookie(for: Defaults.URL.ehentai, key: Defaults.Cookie.ignoreOffensive, value: "1")
        setOrEditCookie(for: Defaults.URL.exhentai, key: Defaults.Cookie.ignoreOffensive, value: "1")
    }
    func fulfillAnotherHostField() {
        let ehURL = Defaults.URL.ehentai
        let exURL = Defaults.URL.exhentai
        let memberIdKey = Defaults.Cookie.ipbMemberId
        let passHashKey = Defaults.Cookie.ipbPassHash
        let ehMemberId = getCookie(ehURL, memberIdKey).rawValue
        let ehPassHash = getCookie(ehURL, passHashKey).rawValue
        let exMemberId = getCookie(exURL, memberIdKey).rawValue
        let exPassHash = getCookie(exURL, passHashKey).rawValue

        if !ehMemberId.isEmpty && !ehPassHash.isEmpty && (exMemberId.isEmpty || exPassHash.isEmpty) {
            setOrEditCookie(for: exURL, key: memberIdKey, value: ehMemberId)
            setOrEditCookie(for: exURL, key: passHashKey, value: ehPassHash)
        } else if !exMemberId.isEmpty && !exPassHash.isEmpty && (ehMemberId.isEmpty || ehPassHash.isEmpty) {
            setOrEditCookie(for: ehURL, key: memberIdKey, value: exMemberId)
            setOrEditCookie(for: ehURL, key: passHashKey, value: exPassHash)
        }
    }
    func loadCookiesState(host: GalleryHost) -> CookiesState {
        let igneousKey = Defaults.Cookie.igneous
        let memberIDKey = Defaults.Cookie.ipbMemberId
        let passHashKey = Defaults.Cookie.ipbPassHash
        let igneous = getCookie(host.url, igneousKey)
        let memberID = getCookie(host.url, memberIDKey)
        let passHash = getCookie(host.url, passHashKey)
        return .init(
            host: host,
            igneous: .init(key: igneousKey, value: igneous, editingText: igneous.rawValue),
            memberID: .init(key: memberIDKey, value: memberID, editingText: memberID.rawValue),
            passHash: .init(key: passHashKey, value: passHash, editingText: passHash.rawValue)
        )
    }
    func getCookiesDescription(host: GalleryHost) -> String {
        var dictionary = [String: String]()
        [Defaults.Cookie.igneous, Defaults.Cookie.ipbMemberId, Defaults.Cookie.ipbPassHash].forEach { key in
            let cookieValue = getCookie(host.url, key)
            if !cookieValue.rawValue.isEmpty {
                dictionary[key] = cookieValue.rawValue
            }
        }
        return dictionary.description
    }
}

// MARK: SetCookies
extension CookieClient {
    func setCookies(state: CookiesState, trimsSpaces: Bool = true) {
        for subState in state.allCases {
            for cookie in state.host.cookieURLs {
                setOrEditCookie(
                    for: cookie,
                    key: subState.key,
                    value: trimsSpaces
                    ? subState.editingText .trimmingCharacters(in: .whitespaces) : subState.editingText
                )
            }
        }

    }
    func setCredentials(response: HTTPURLResponse) {
        guard let setString = response.allHeaderFields["Set-Cookie"] as? String else { return }
        setString.components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: "; ") }.forEach { value in
                [Defaults.URL.ehentai, Defaults.URL.exhentai].forEach { url in
                    [
                        Defaults.Cookie.ipbMemberId,
                        Defaults.Cookie.ipbPassHash,
                        Defaults.Cookie.igneous
                    ].forEach { key in
                        guard !(url == Defaults.URL.ehentai && key == Defaults.Cookie.igneous),
                              let range = value.range(of: "\(key)=") else { return }
                        setCookie(for: url, key: key, value: String(value[range.upperBound...]))
                    }
                }
            }
    }
    func setSkipServer(response: HTTPURLResponse) {
        guard let setString = response.allHeaderFields["Set-Cookie"] as? String else { return }
        setString.components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: "; ") }
            .forEach { value in
                let key = Defaults.Cookie.skipServer
                if let range = value.range(of: "\(key)=") {
                    setCookie(
                        for: Defaults.URL.host, key: key,
                        value: String(value[range.upperBound...]), path: "/s/"
                    )
                }
            }
    }
}

// MARK: API
enum CookieClientKey: DependencyKey {
    static let liveValue = CookieClient.live
    static let previewValue = CookieClient.noop
    static let testValue = CookieClient.unimplemented
}

extension DependencyValues {
    var cookieClient: CookieClient {
        get { self[CookieClientKey.self] }
        set { self[CookieClientKey.self] = newValue }
    }
}

// MARK: Test
extension CookieClient {
    static let noop: Self = .init(
        clearAll: {},
        getCookie: { _, _ in .empty },
        removeCookie: { _, _ in },
        checkExistence: { _, _ in false },
        initializeCookie: { _, _ in .init() }
    )

    static func placeholder<Result>() -> Result { fatalError() }

    static let unimplemented: Self = .init(
        clearAll: IssueReporting.unimplemented(placeholder: placeholder()),
        getCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        removeCookie: IssueReporting.unimplemented(placeholder: placeholder()),
        checkExistence: IssueReporting.unimplemented(placeholder: placeholder()),
        initializeCookie: IssueReporting.unimplemented(placeholder: placeholder())
    )
}
