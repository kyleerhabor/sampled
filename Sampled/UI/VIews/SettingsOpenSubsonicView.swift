//
//  SettingsOpenSubsonicView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/6/26.
//

import Algorithms
import CryptoKit
import HTTPTypes
@preconcurrency import OpenAPIKit30
import OpenAPIRuntime
import OpenAPIURLSession
import OSLog
import SwiftUI
import SampledOpenSubsonicAPI

let openAPIDocument = try! JSONDecoder().decode(
  OpenAPI.Document.self,
  from: try! Data(contentsOf: URL(filePath: openAPIFilePath, directoryHint: .notDirectory)),
)

struct OpenSubsonicGlobalParametersClientMiddlewareAPIKeyAuthenticationMethod {
  let key: String
}

struct OpenSubsonicGlobalParametersClientMiddlewareLoginAuthenticationMethod {
  let username: String
  let password: String
}

enum OpenSubsonicGlobalParametersClientMiddlewareAuthenticationMethod {
  case apiKey(OpenSubsonicGlobalParametersClientMiddlewareAPIKeyAuthenticationMethod),
       login(OpenSubsonicGlobalParametersClientMiddlewareLoginAuthenticationMethod)
}

struct OpenSubsonicGlobalParametersClientMiddleware: ClientMiddleware {
  static private let saltCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  static private let saltLength = 6
  // I don't think it's a good idea to make this configurable since a renamed client would functionally be the same.
  static private let clientName = "Sampled"
  static private let format = "json"
  private let document: OpenAPI.Document
  private let authenticationMethod: OpenSubsonicGlobalParametersClientMiddlewareAuthenticationMethod

  init(
    document: OpenAPI.Document,
    authenticationMethod: OpenSubsonicGlobalParametersClientMiddlewareAuthenticationMethod,
  ) {
    self.document = document
    self.authenticationMethod = authenticationMethod
  }

  static private func generateSalt() -> String {
    // TODO: Allow duplicate characters.
    let selected = Self.saltCharacters.randomSample(count: Self.saltLength)
    let salt = String(selected)

    return salt
  }

  private struct WriteState {
    let components: URLComponents

    init(components: URLComponents) {
      self.components = components
    }
  }

  static private func write(_ state: WriteState, securityScheme: OpenAPI.SecurityScheme, value: String) -> WriteState {
    switch securityScheme.type {
      case let .apiKey(name: name, location: location):
        switch location {
          case .query:
            var components = state.components
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: name, value: value))

            components.queryItems = items

            return WriteState(components: components)
          case .header, .cookie:
            unreachable()
        }
      case .http, .oauth2, .openIdConnect:
        unreachable()
    }
  }

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: OpenAPIRuntime.HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPTypes.HTTPRequest, OpenAPIRuntime.HTTPBody?, URL) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?)
  ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
    let securitySchemeAPIKey = self.document.components.securitySchemes["apiKeyAuth"]!
    let securitySchemeUsername = self.document.components.securitySchemes["username"]!
    let securitySchemeToken = self.document.components.securitySchemes["token"]!
    let securitySchemeSalt = self.document.components.securitySchemes["salt"]!
    let securitySchemeProtocolVersion = self.document.components.securitySchemes["protocolVersion"]!
    let securitySchemeClientName = self.document.components.securitySchemes["clientName"]!
    let securitySchemeFormat = self.document.components.securitySchemes["format"]!
    var state = WriteState(components: URLComponents(string: request.path ?? "")!)

    switch self.authenticationMethod {
      case let .apiKey(apiKey):
        state = Self.write(state, securityScheme: securitySchemeAPIKey, value: apiKey.key)
      case let .login(login):
        // As far as I'm aware, implementations like Navidrome don't support API key authentication as of v0.61.2.
        let salt = Self.generateSalt()
        let input = login.password + salt
        let token = Insecure.MD5
          .hash(data: Data(input.utf8))
          .hexEncodedString()

        state = Self.write(state, securityScheme: securitySchemeUsername, value: login.username)
        state = Self.write(state, securityScheme: securitySchemeToken, value: token)
        state = Self.write(state, securityScheme: securitySchemeSalt, value: salt)
    }

    state = Self.write(state, securityScheme: securitySchemeProtocolVersion, value: self.document.info.version)
    state = Self.write(state, securityScheme: securitySchemeClientName, value: Self.clientName)
    // The document assumes that responses are in JSON, so we may as well assume that as the format, too.
    state = Self.write(state, securityScheme: securitySchemeFormat, value: Self.format)

    var request = request
    request.path = state.components.string

    return try await next(request, body, baseURL)
  }
}

@Observable
@MainActor
class SettingsOpenSubsonicLibraryModel {
  var location: String
  var authenticationMethod: StorageOpenSubsonicLibrarySourceAuthenticationMethod
  var apiKey: String
  var username: String
  var password: String

  init(
    location: String,
    authenticationMethod: StorageOpenSubsonicLibrarySourceAuthenticationMethod,
    apiKey: String,
    username: String,
    password: String,
  ) {
    self.location = location
    self.authenticationMethod = authenticationMethod
    self.apiKey = apiKey
    self.username = username
    self.password = password
  }
}

struct SettingsOpenSubsonicTestConnectionInvalidLocationError {
  let location: String
}

enum SettingsOpenSubsonicTestConnectionErrorType {
  case invalidLocation(SettingsOpenSubsonicTestConnectionInvalidLocationError),
       // TODO: Rename.
       badResponse,
       invalidResponse,
       incompatibleClientProtocolVersion,
       incompatibleServerProtocolVersion,
       wrongUsernamePassword,
       authenticationMethodAPIKeyUnsupported,
       authenticationMethodLoginUnsupported,
       invalidAPIKey
}

struct SettingsOpenSubsonicTestConnectionError {
  let type: SettingsOpenSubsonicTestConnectionErrorType
  let locale: Locale
}

extension SettingsOpenSubsonicTestConnectionError: LocalizedError {
  var errorDescription: String? {
    switch self.type {
      case let .invalidLocation(error):
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidLocation.Location.\(error.location)",
          locale: self.locale,
        )
      case .badResponse:
        String(localized: "Settings.General.LibrarySource.OpenSubsonic.Error.BadResponse", locale: self.locale)
      case .invalidResponse:
        String(localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidResponse", locale: self.locale)
      case .incompatibleClientProtocolVersion:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.IncompatibleClientProtocolVersion",
          locale: self.locale,
        )
      case .incompatibleServerProtocolVersion:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.IncompatibleServerProtocolVersion",
          locale: self.locale,
        )
      case .wrongUsernamePassword:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.WrongUsernamePassword",
          locale: self.locale,
        )
      case .authenticationMethodAPIKeyUnsupported:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.AuthenticationMethodAPIKeyUnsupported",
          locale: self.locale,
        )
      case .authenticationMethodLoginUnsupported:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.AuthenticationMethodLoginUnsupported",
          locale: self.locale,
        )
      case .invalidAPIKey:
        String(localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidAPIKey", locale: self.locale)
    }
  }

  var recoverySuggestion: String? {
    switch self.type {
      case .invalidLocation:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidLocation.RecoverySuggestion",
          locale: self.locale,
        )
      case .badResponse:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.BadResponse.RecoverySuggestion",
          locale: self.locale,
        )
      case .invalidResponse:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidResponse.RecoverySuggestion",
          locale: self.locale,
        )
      case .incompatibleClientProtocolVersion:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.IncompatibleClientProtocolVersion.RecoverySuggestion",
          locale: self.locale,
        )
      case .incompatibleServerProtocolVersion:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.IncompatibleServerProtocolVersion.RecoverySuggestion",
          locale: self.locale,
        )
      case .wrongUsernamePassword:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.WrongUsernamePassword.RecoverySuggestion",
          locale: self.locale,
        )
      case .authenticationMethodAPIKeyUnsupported:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.AuthenticationMethodAPIKeyUnsupported.RecoverySuggestion",
          locale: self.locale,
        )
      case .authenticationMethodLoginUnsupported:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.AuthenticationMethodLoginUnsupported.RecoverySuggestion",
          locale: self.locale,
        )
      case .invalidAPIKey:
        String(
          localized: "Settings.General.LibrarySource.OpenSubsonic.Error.InvalidAPIKey.RecoverySuggestion",
          locale: self.locale,
        )
    }
  }
}

struct SettingsOpenSubsonicView: View {
  static private let urlPrompt = "https://demo.navidrome.org"
  static private let usernamePrompt = "demo"
  static private let passwordPrompt = "demo"
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @Bindable var library: SettingsOpenSubsonicLibraryModel
  @AppStorage(StorageKeys.librarySourceOpenSubsonicLocation) private var location
  @AppStorage(StorageKeys.librarySourceOpenSubsonicAuthenticationMethod) private var authenticationMethod
  @State private var isTestConnectionSuccessActive = false
  @State private var testConnectionError: SettingsOpenSubsonicTestConnectionError?
  @State private var isTestConnectionErrorActive = false

  var body: some View {
    Form {
      Section {
        TextField(text: $library.location, prompt: Text(verbatim: Self.urlPrompt)) {
          Text("Settings.General.LibrarySource.OpenSubsonic.Location")
          Text("Settings.General.LibrarySource.OpenSubsonic.Location.Note")
        }
        .textContentType(.URL)

        Picker(
          "Settings.General.LibrarySource.OpenSubsonic.AuthenticationMethod",
          selection: $library.authenticationMethod,
        ) {
          Section {
            Text("Settings.General.LibrarySource.OpenSubsonic.AuthenticationMethod.None")
              .tag(StorageOpenSubsonicLibrarySourceAuthenticationMethod.none, includeOptional: false)
          }

          Section {
            Text("Settings.General.LibrarySource.OpenSubsonic.AuthenticationMethod.APIKey")
              .tag(StorageOpenSubsonicLibrarySourceAuthenticationMethod.apiKey, includeOptional: false)

            Text("Settings.General.LibrarySource.OpenSubsonic.AuthenticationMethod.Login")
              .tag(StorageOpenSubsonicLibrarySourceAuthenticationMethod.login, includeOptional: false)
          }
        }
      }

      Section("Settings.General.LibrarySource.OpenSubsonic.APIKey") {
        SecureField("Settings.General.LibrarySource.OpenSubsonic.APIKey.Key", text: $library.apiKey)
      }
      .disabled(self.library.authenticationMethod != .apiKey)

      Section("Settings.General.LibrarySource.OpenSubsonic.Login") {
        TextField(
          "Settings.General.LibrarySource.OpenSubsonic.Login.Username",
          text: $library.username,
          prompt: Text(verbatim: Self.usernamePrompt),
        )
        .textContentType(.username)

        SecureField(
          "Settings.General.LibrarySource.OpenSubsonic.Login.Password",
          text: $library.password,
          prompt: Text(verbatim: Self.passwordPrompt),
        )
        .textContentType(.password)
      }
      .disabled(self.library.authenticationMethod != .login)
    }
    .formStyle(.grouped)
    .presentationSizing(.fitted)
    .toolbar {
      ToolbarItem {
        HStack {
          Button("Settings.General.LibrarySource.OpenSubsonic.TestConnection") {
            self.testConnection()
          }
          .alert(isPresented: $isTestConnectionErrorActive, error: self.testConnectionError) { error in
            // Empty
          } message: { error in
            Text(error.recoverySuggestion ?? "")
          }
          .disabled(
            self.library.authenticationMethod == .none
            || self.library.authenticationMethod == .apiKey && self.library.apiKey.isEmpty
            || self.library.authenticationMethod == .login && self.library.username.isEmpty
          )

          Image(systemName: "checkmark.circle")
            .symbolVariant(.fill)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary, .green)
            .visible(self.isTestConnectionSuccessActive)
        }
      }

      ToolbarItem(placement: .cancellationAction) {
        Button("Settings.General.LibrarySource.OpenSubsonic.Cancel", role: .cancel) {
          self.dismiss()
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Settings.General.LibrarySource.OpenSubsonic.Save") {
          Task {
            guard await Self.perform(
              x: SettingsView.X(
                apiKey: self.library.apiKey,
                username: self.library.username,
                password: self.library.password,
              ),
            ) else {
              return
            }

            self.location = self.library.location
            self.authenticationMethod = self.library.authenticationMethod
            self.dismiss()
          }
        }
      }
    }
  }

  private func testConnection() {
    let url: URL

    do {
      url = try Servers.Server1.url(url: self.library.location)
    } catch {
      Logger.ui.error("\(error)")

      self.testConnectionError = SettingsOpenSubsonicTestConnectionError(
        type: .invalidLocation(SettingsOpenSubsonicTestConnectionInvalidLocationError(location: self.library.location)),
        locale: self.locale,
      )

      self.isTestConnectionErrorActive = true

      return
    }

    let authenticationMethod: OpenSubsonicGlobalParametersClientMiddlewareAuthenticationMethod = switch self.library.authenticationMethod {
      case .none:
        unreachable()
      case .apiKey:
        .apiKey(OpenSubsonicGlobalParametersClientMiddlewareAPIKeyAuthenticationMethod(key: self.library.apiKey))
      case .login:
        .login(
          OpenSubsonicGlobalParametersClientMiddlewareLoginAuthenticationMethod(
            username: self.library.username,
            password: self.library.password,
          ),
        )
    }
    
    let client = Client(
      serverURL: url,
      configuration: Configuration(jsonEncodingOptions: []),
      transport: URLSessionTransport(),
      middlewares: [
        OpenSubsonicGlobalParametersClientMiddleware(
          document: openAPIDocument,
          authenticationMethod: authenticationMethod,
        ),
      ],
    )

    Task {
      let response: Operations.Ping.Output

      do {
        response = try await client.ping(
          Operations.Ping.Input(
            headers: Operations.Ping.Input.Headers(
              accept: [AcceptHeaderContentType(contentType: .json)],
            ),
          ),
        )
      } catch {
        Logger.ui.error("\(error)")

        self.testConnectionError = SettingsOpenSubsonicTestConnectionError(type: .badResponse, locale: self.locale)
        self.isTestConnectionErrorActive = true

        return
      }

      let ok: Components.Responses.EmptySubsonicResponse

      do {
        ok = try response.ok
      } catch {
        Logger.model.error("\(error)")

        self.testConnectionError = SettingsOpenSubsonicTestConnectionError(type: .invalidResponse, locale: self.locale)
        self.isTestConnectionErrorActive = true

        return
      }

      let body: Components.Schemas.SubsonicResponse

      do {
        body = try ok.body.json
      } catch {
        Logger.model.error("\(error)")

        self.testConnectionError = SettingsOpenSubsonicTestConnectionError(type: .invalidResponse, locale: self.locale)
        self.isTestConnectionErrorActive = true

        return
      }

      guard let subsonicResponse = body.subsonicResponse else {
        self.testConnectionError = SettingsOpenSubsonicTestConnectionError(type: .invalidResponse, locale: self.locale)
        self.isTestConnectionErrorActive = true

        return
      }

      switch subsonicResponse {
        case .SubsonicSuccessResponse:
          break
        case let .SubsonicFailureResponse(failure):
          // TODO: Implement 41: Token authentication not supported for LDAP users.
          //
          // This requires retrying the request.
          switch failure.value2.error.code {
            // Incompatible Subsonic REST protocol version. Client must upgrade.
            case ._20:
              self.testConnectionError = SettingsOpenSubsonicTestConnectionError(
                type: .incompatibleClientProtocolVersion,
                locale: self.locale,
              )
            // Incompatible Subsonic REST protocol version. Server must upgrade.
            case ._30:
              self.testConnectionError = SettingsOpenSubsonicTestConnectionError(
                type: .incompatibleServerProtocolVersion,
                locale: self.locale,
              )
            // Wrong username or password.
            //
            // Navidrome returns this as of v0.61.2 instead of code 42, which is annoying.
            case ._40:
              self.testConnectionError = SettingsOpenSubsonicTestConnectionError(
                type: .wrongUsernamePassword,
                locale: self.locale,
              )
            // Provided authentication mechanism not supported.
            case ._42:
              let type: SettingsOpenSubsonicTestConnectionErrorType = switch self.library.authenticationMethod {
                case .none:
                  unreachable()
                case .apiKey:
                  .authenticationMethodAPIKeyUnsupported
                case .login:
                  .authenticationMethodLoginUnsupported
              }

              self.testConnectionError = SettingsOpenSubsonicTestConnectionError(type: type, locale: self.locale)
            // Invalid API key.
            case ._44:
              self.testConnectionError = SettingsOpenSubsonicTestConnectionError(
                type: .invalidAPIKey,
                locale: self.locale,
              )
            default:
              Logger.ui.error("\(failure.value2.error.code.rawValue)")

              return
          }

          self.isTestConnectionErrorActive = true

          return
      }

      self.isTestConnectionSuccessActive = true

      // TODO: Extract.
      do {
        try await Task.sleep(for: .seconds(3))
      } catch is CancellationError {
        // Fallthrough
      } catch {
        unreachable()
      }

      self.isTestConnectionSuccessActive = false
    }
  }

  nonisolated private static func upsert(
    addQuery: CFDictionary,
    updateQuery: CFDictionary,
    updateAttributes: CFDictionary,
  ) -> OSStatus {
    let addStatus = SecItemAdd(addQuery, nil)

    guard addStatus == errSecDuplicateItem else {
      return addStatus
    }

    let updateStatus = SecItemUpdate(updateQuery, updateAttributes)

    return updateStatus
  }

  nonisolated private static func perform(x: SettingsView.X) async -> Bool {
    var error: Unmanaged<CFError>?
    let result = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleAfterFirstUnlock,
      SecAccessControlCreateFlags(),
      &error,
    )

    if let error {
      Logger.ui.error("\(error.takeRetainedValue())")

      return false
    }

    let accessControl = result!
    let apiKeyValue = x.apiKey.data(using: .utf8)!
    let addAPIKeyQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecValueData: apiKeyValue,
      kSecAttrService: SettingsView.openSubsonicAPIKey,
      kSecUseDataProtectionKeychain: true,
      kSecAttrAccessControl: accessControl,
    ]

    let updateAPIKeyQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: SettingsView.openSubsonicAPIKey,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain: true,
    ]

    let updateAPIKeyAttributes = [kSecValueData: apiKeyValue]
    let apiKeyStatus = Self.upsert(
      addQuery: addAPIKeyQuery as CFDictionary,
      updateQuery: updateAPIKeyQuery as CFDictionary,
      updateAttributes: updateAPIKeyAttributes as CFDictionary,
    )

    guard apiKeyStatus == errSecSuccess else {
      Logger.ui.error("\(apiKeyStatus)")

      return false
    }

    let loginValue = x.password.data(using: .utf8)!
    let addLoginQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecValueData: loginValue,
      kSecAttrAccount: x.username,
      kSecAttrService: SettingsView.openSubsonicLogin,
      kSecUseDataProtectionKeychain: true,
      kSecAttrAccessControl: accessControl,
    ]

    let updateLoginQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: x.username,
      kSecAttrService: SettingsView.openSubsonicLogin,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecUseDataProtectionKeychain: true,
    ]

    let updateLoginAttributes = [kSecValueData: loginValue]
    let loginStatus = Self.upsert(
      addQuery: addLoginQuery as CFDictionary,
      updateQuery: updateLoginQuery as CFDictionary,
      updateAttributes: updateLoginAttributes as CFDictionary,
    )

    guard loginStatus == errSecSuccess else {
      Logger.ui.error("\(loginStatus)")

      return false
    }

    return true
  }
}

