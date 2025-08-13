class BaseService {
  Future<T> handleError<T>(Future<T> Function() function) async {
    try {
      return await function();
    } catch (e) {
      print('Error in service: $e');
      throw ServiceException('An error occurred: $e');
    }
  }
}

class ServiceException implements Exception {
  final String message;
  ServiceException(this.message);

  @override
  String toString() => message;
}
