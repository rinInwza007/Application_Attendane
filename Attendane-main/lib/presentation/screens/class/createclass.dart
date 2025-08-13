import 'package:flutter/material.dart';
import 'package:myproject2/data/services/auth_service.dart';


class CreateClassDialog extends StatefulWidget {
  final Function onClassCreated;

  const CreateClassDialog({
    super.key,
    required this.onClassCreated,
  });

  @override
  State<CreateClassDialog> createState() => _CreateClassDialogState();
}

class _CreateClassDialogState extends State<CreateClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _classIdController = TextEditingController();
  final _classNameController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _roomController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _classIdController.dispose();
    _classNameController.dispose();
    _scheduleController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _createClass() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // เช็คว่ามี class_id นี้อยู่แล้วหรือไม่
      final existing =
          await AuthService().checkClassExists(_classIdController.text.trim());

      if (existing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class ID already exists'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      await AuthService().createClass(
        classId: _classIdController.text.trim(),
        className: _classNameController.text.trim(),
        schedule: _scheduleController.text.trim(),
        room: _roomController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onClassCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating class: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // ในส่วน Widget build(BuildContext context)
// แก้ไขส่วน Column children โดยลบ TextFormField ของ Class ID ที่ซ้ำกันออก
// และเพิ่ม TextFormField สำหรับ Room

              children: [
                const Text(
                  'Create New Class',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _classIdController,
                  decoration: const InputDecoration(
                    labelText: 'Class ID',
                    hintText: 'e.g., CS101',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter class ID';
                    }
                    if (!RegExp(r'^[A-Z0-9]{2,10}$').hasMatch(value)) {
                      return 'Class ID must be 2-10 characters (A-Z, 0-9)';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.characters,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _classNameController,
                  decoration: const InputDecoration(
                    labelText: 'Class Name',
                    hintText: 'e.g., Introduction to Programming',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter class name';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _scheduleController,
                  decoration: const InputDecoration(
                    labelText: 'Schedule',
                    hintText: 'e.g., Mon, Wed 10:00-11:30',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter schedule';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller:
                      _roomController, // เพิ่ม TextFormField สำหรับ Room
                  decoration: const InputDecoration(
                    labelText: 'Room',
                    hintText: 'e.g., R401',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter room';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _createClass,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
