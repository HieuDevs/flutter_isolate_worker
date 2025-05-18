import 'dart:math';

/// Generates a unique ID using a combination of timestamp and random numbers.
/// This is a simpler version that doesn't use cryptographic hashing.
String generateUniqueId() {
  // Get current timestamp in milliseconds
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  // Generate random string
  final random = Random.secure();
  final randomStr =
      List.generate(8, (_) => random.nextInt(36)).map((n) {
        // Convert numbers 0-9 to strings directly
        if (n < 10) return n.toString();
        // Convert numbers 10-35 to lowercase letters a-z
        // ASCII 'a' is 97, so we add 87 (97-10) to get the right character
        return String.fromCharCode(n + 87);
      }).join();

  // Combine timestamp and random string
  return '${timestamp.toRadixString(36)}$randomStr';
}
