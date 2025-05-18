class Logger {
  static const String _reset = '\x1B[0m';
  static const String _blue = '\x1B[34m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';

  static void info(String message) {
    print('$_blue[INFO]$_reset $message');
  }

  static void success(String message) {
    print('$_green[SUCCESS]$_reset $message');
  }

  static void warning(String message) {
    print('$_yellow[WARNING]$_reset $message');
  }

  static void error(String message) {
    print('$_red[ERROR]$_reset $message');
  }

  static void task(String id, String message) {
    print('$_blue[Task $_green$id$_blue]$_reset $message');
  }

  static void taskComplete(String id, int milliseconds) {
    print('$_blue[Task $_green$id$_blue]$_reset Completed in $_green${milliseconds}ms$_reset');
  }
}
