/// Настройки источника обновлений.
///
/// Укажите свой логин и репозиторий после публикации на GitHub.
/// Можно переопределить при сборке, не меняя код:
///
///     flutter build apk --release \
///       --dart-define=GITHUB_OWNER=my-login \
///       --dart-define=GITHUB_REPO=vguit_app
const String kGithubOwner = String.fromEnvironment(
  'GITHUB_OWNER',
  defaultValue: 'hayatodzava',
);

const String kGithubRepo = String.fromEnvironment(
  'GITHUB_REPO',
  defaultValue: 'vguit_app',
);

/// Настроен ли репозиторий (иначе проверка обновлений не выполняется).
bool get isUpdateConfigured => !kGithubOwner.startsWith('YOUR_');

/// Адрес последнего релиза через API GitHub.
String get latestReleaseApiUrl =>
    'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest';

/// Страница релизов — открывается, если в релизе нет APK.
String get releasesPageUrl =>
    'https://github.com/$kGithubOwner/$kGithubRepo/releases';
