import '../../../l10n/app_localizations.dart';

enum ChatConnectionState {
  connecting,
  connected,
  reconnecting,
  offline,
  error,
}

String chatConnectionLabel(ChatConnectionState state, AppLocalizations l10n) {
  switch (state) {
    case ChatConnectionState.connecting:
      return l10n.t('chat_connection_connecting');
    case ChatConnectionState.connected:
      return l10n.t('chat_connection_connected');
    case ChatConnectionState.reconnecting:
      return l10n.t('chat_connection_reconnecting');
    case ChatConnectionState.offline:
      return l10n.t('chat_connection_offline');
    case ChatConnectionState.error:
      return l10n.t('chat_connection_error');
  }
}
