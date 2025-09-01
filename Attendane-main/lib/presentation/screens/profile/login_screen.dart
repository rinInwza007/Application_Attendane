import 'package:flutter/material.dart';
import 'package:myproject2/presentation/screens/auth/register_screen.dart';
import 'package:myproject2/presentation/screens/profile/inputdata.dart';
import 'package:myproject2/presentation/screens/profile/updated_profile.dart' hide Text; // เปลี่ยนจาก profile.dart
import 'package:myproject2/presentation/screens/profile/profileteachaer.dart';
import 'package:myproject2/data/services/auth_service.dart';
import '../../common_widgets/app_button.dart';
import '../../common_widgets/app_text_field.dart';
import '../../common_widgets/loading_overlay.dart';
import '../../common_widgets/error_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  final _authService = AuthService(); 

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.signInWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      // Check user profile and type
      final profileData = await _authService.checkUserProfile();

      if (!mounted) return;

      if (!profileData['exists']) {
        _navigateToInputDataScreen();
      } else {
        // Navigate based on user type
        final userType = profileData['userType'];
        _navigateToProfileScreen(userType);
      }
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(
          context,
          title: 'Login Failed',
          message: 'Invalid email or password. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToInputDataScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const InputDataPage()),
    );
  }

  void _navigateToProfileScreen(String? userType) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            userType == 'teacher' ? const TeacherProfile() : const UpdatedProfile(), // เปลี่ยนจาก Profile() เป็น UpdatedProfile()
      ),
    );
  }

  void _navigateToRegisterScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LoadingOverlay(
        isLoading: _isLoading,
        loadingText: 'Signing in...',
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildLoginForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 80,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          "Attendance Plus",
          style: TextStyle(
            fontSize: 32,
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Sign in to continue",
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'Enter your email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                  .hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
            enabled: !_isLoading,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            hint: 'Enter your password',
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
            ),
            obscureText: !_isPasswordVisible,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
            enabled: !_isLoading,
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Login',
            onPressed: _login,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "No account? ",
                style: TextStyle(color: Colors.grey[600]),
              ),
              GestureDetector(
                onTap: _isLoading ? null : _navigateToRegisterScreen,
                child: Text(
                  "Sign Up",
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}