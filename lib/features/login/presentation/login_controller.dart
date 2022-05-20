import 'package:core/core.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:model/model.dart';
import 'package:tmail_ui_user/features/login/domain/state/authentication_user_state.dart';
import 'package:tmail_ui_user/features/login/domain/state/check_oidc_is_available_state.dart';
import 'package:tmail_ui_user/features/login/domain/state/get_oidc_configuration_state.dart';
import 'package:tmail_ui_user/features/login/domain/state/get_token_oidc_state.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/authentication_user_interactor.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/check_oidc_is_available_interactor.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/get_oidc_configuration_interactor.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/get_token_oidc_interactor.dart';
import 'package:tmail_ui_user/features/login/presentation/login_form_type.dart';
import 'package:tmail_ui_user/features/login/presentation/state/login_state.dart';
import 'package:tmail_ui_user/main/routes/app_routes.dart';
import 'package:tmail_ui_user/main/routes/route_navigation.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';

class LoginController extends GetxController {

  final AuthenticationInteractor _authenticationInteractor;
  final DynamicUrlInterceptors _dynamicUrlInterceptors;
  final AuthorizationInterceptors _authorizationInterceptors;
  final CheckOIDCIsAvailableInteractor _checkOIDCIsAvailableInteractor;
  final GetOIDCConfigurationInteractor _getOIDCConfigurationInteractor;
  final GetTokenOIDCInteractor _getTokenOIDCInteractor;

  final TextEditingController urlInputController = TextEditingController();

  LoginController(
    this._authenticationInteractor,
    this._dynamicUrlInterceptors,
    this._authorizationInterceptors,
    this._checkOIDCIsAvailableInteractor,
    this._getOIDCConfigurationInteractor,
    this._getTokenOIDCInteractor,
  );

  var loginState = LoginState(Right(LoginInitAction())).obs;
  final loginFormType = LoginFormType.baseUrlForm.obs;

  String? _urlText;
  String? _userNameText;
  String? _passwordText;

  void setUrlText(String url) => _urlText = url.trim().formatURLValid();

  void setUserNameText(String userName) => _userNameText = userName;

  void setPasswordText(String password) => _passwordText = password;

  Uri? _parseUri(String? url) => url != null && url.trim().isNotEmpty
      ? Uri.parse(url.trim())
      : null;

  UserName? _parseUserName(String? userName) => userName != null && userName.trim().isNotEmpty
      ? UserName(userName.trim())
      : null;

  Password? _parsePassword(String? password) => password != null && password.trim().isNotEmpty
      ? Password(password.trim())
      : null;

  void handleNextInUrlInputFormPress() {
    _checkOIDCIsAvailable();
  }

  void _checkOIDCIsAvailable() async {
    final baseUri = BuildUtils.isWeb ? _parseUri(AppConfig.baseUrl) : _parseUri(_urlText);
    log('LoginController::_checkOIDCIsAvailable(): baseUri: $baseUri');
    if (baseUri == null) {
      loginState.value = LoginState(Left(LoginMissUrlAction()));
    } else {
      loginState.value = LoginState(Right(LoginLoadingAction()));
      await _checkOIDCIsAvailableInteractor
          .execute(OIDCRequest(baseUrl: baseUri.origin))
          .then((response) => response.fold(
              (failure) => _showFormLoginWithCredentialAction(),
              (success) => success is CheckOIDCIsAvailableSuccess
                  ? _showFormLoginWithSSOAction(success)
                  : _showFormLoginWithCredentialAction()));
    }
  }

  void _showFormLoginWithSSOAction(CheckOIDCIsAvailableSuccess success) {
    loginState.value = LoginState(Right(success));
    loginFormType.value = LoginFormType.ssoForm;
  }

  void handleBackInCredentialForm() {
    loginState.value = LoginState(Right(LoginInitAction()));
    loginFormType.value = LoginFormType.baseUrlForm;
  }

  void _showFormLoginWithCredentialAction() {
    loginState.value = LoginState(Right(InputUrlCompletion()));
    loginFormType.value = LoginFormType.credentialForm;
  }

  void handleLoginPressed() {
    if (loginFormType.value == LoginFormType.ssoForm) {
      final baseUri = kIsWeb ? _parseUri(AppConfig.baseUrl) : _parseUri(_urlText);
      if (baseUri != null) {
        _getOIDCConfiguration(baseUri);
      } else {
        loginState.value = LoginState(Left(LoginMissUrlAction()));
      }
    } else {
      final baseUri = kIsWeb ? _parseUri(AppConfig.baseUrl) : _parseUri(_urlText);
      final userName = _parseUserName(_userNameText);
      final password = _parsePassword(_passwordText);
      if (baseUri != null && userName != null && password != null) {
        _loginAction(baseUri, userName, password);
      } else if (baseUri == null) {
        loginState.value = LoginState(Left(LoginMissUrlAction()));
      } else if (userName == null) {
        loginState.value = LoginState(Left(LoginMissUsernameAction()));
      } else if (password == null) {
        loginState.value = LoginState(Left(LoginMissPasswordAction()));
      }
    }
  }

  void _getOIDCConfiguration(Uri baseUri) async {
    loginState.value = LoginState(Right(LoginLoadingAction()));
    await _getOIDCConfigurationInteractor.execute(baseUri)
        .then((response) => response.fold(
            (failure) {
              if (failure is GetOIDCConfigurationFailure) {
                loginState.value = LoginState(Left(failure));
              } else {
                loginState.value = LoginState(Left(LoginCanNotVerifySSOConfigurationAction()));
              }
            },
            (success) {
              if (success is GetOIDCConfigurationSuccess) {
                _getOIDCConfigurationSuccess(success);
              } else {
                loginState.value = LoginState(Left(LoginCanNotVerifySSOConfigurationAction()));
              }
            }));
  }

  void _getOIDCConfigurationSuccess(GetOIDCConfigurationSuccess success) {
    loginState.value = LoginState(Right(success));
    if (currentContext != null) {
      _getTokenOIDCAction(currentContext!, success.oidcConfiguration);
    }
  }

  void _getTokenOIDCAction(BuildContext context, OIDCConfiguration config) async {
    loginState.value = LoginState(Right(LoginLoadingAction()));
    await _getTokenOIDCInteractor
        .execute(config.clientId, config.redirectUrl, config.discoveryUrl, config.scopes)
        .then((response) => response.fold(
            (failure) {
              if (failure is GetTokenOIDCFailure) {
                loginState.value = LoginState(Left(failure));
              } else {
                loginState.value = LoginState(Left(LoginCanNotGetTokenAction()));
              }
            },
            (success) {
              if (success is GetTokenOIDCSuccess) {
                _getTokenOIDCSuccess(success);
              } else {
                loginState.value = LoginState(Left(LoginCanNotGetTokenAction()));
              }
            }));
  }

  void _getTokenOIDCSuccess(GetTokenOIDCSuccess success) {
    log('LoginController::_getTokenOIDCSuccess(): ');
    loginState.value = LoginState(Right(success));
  }

  void _loginAction(Uri baseUrl, UserName userName, Password password) async {
    loginState.value = LoginState(Right(LoginLoadingAction()));
    await _authenticationInteractor.execute(baseUrl, userName, password)
      .then((response) => response.fold(
        (failure) => failure is AuthenticationUserFailure ? _loginFailureAction(failure) : null,
        (success) => success is AuthenticationUserViewState ? _loginSuccessAction(success) : null));
  }

  void _loginSuccessAction(AuthenticationUserViewState success) {
    loginState.value = LoginState(Right(success));
    _dynamicUrlInterceptors.changeBaseUrl(kIsWeb ? AppConfig.baseUrl : _urlText);
    _authorizationInterceptors.changeAuthorization(_userNameText, _passwordText);
    pushAndPop(AppRoutes.SESSION);
  }

  void _loginFailureAction(FeatureFailure failure) {
    loginState.value = LoginState(Left(failure));
  }

  void formatUrl(String url) {
    log('LoginController::formatUrl(): $url');
    if (url.isValid()) {
      urlInputController.text = url.removePrefix();
    }
    setUrlText(urlInputController.text);
  }

  @override
  void onClose() {
    urlInputController.clear();
    super.onClose();
  }
}