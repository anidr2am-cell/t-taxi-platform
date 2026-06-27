enum ChatConnectionState {
  connecting,
  connected,
  reconnecting,
  offline,
  error,
}

String chatConnectionLabel(ChatConnectionState state) {
  switch (state) {
    case ChatConnectionState.connecting:
      return 'Connecting…';
    case ChatConnectionState.connected:
      return 'Live';
    case ChatConnectionState.reconnecting:
      return 'Reconnecting…';
    case ChatConnectionState.offline:
      return 'Offline';
    case ChatConnectionState.error:
      return 'Connection error';
  }
}
