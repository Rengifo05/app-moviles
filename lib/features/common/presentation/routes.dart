/// Rutas de la app.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const signIn = '/auth/sign-in';
  static const signUp = '/auth/sign-up';
  static const resetPassword = '/auth/reset';
  static const familySetup = '/family-setup';
  static const createFamily = '/family-setup/create';
  static const joinFamily = '/family-setup/join';
  static const home = '/home';
  static const map = '/map';
  static const activity = '/activity';
  static const family = '/family';
  static const settings = '/settings';
  static const invite = '/family/invite';
  static const checkIn = '/check-in';
  static const sos = '/sos';
  static const newZone = '/map/zones/new';
  static String zone(String id) => '/map/zones/$id';
  static String member(String uid) => '/family/members/$uid';
  static const privacy = '/settings/privacy';
  static const account = '/settings/account';
}
