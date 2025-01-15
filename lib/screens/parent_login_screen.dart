import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:parentseye_parent/models/login_response_model.dart';
import 'package:parentseye_parent/screens/branch_login_related/devices_list_screen.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../provider/auth_provider.dart';
import 'dashboard.dart';
import 'help_support.dart';

class ParentalLogin extends StatefulWidget {
  const ParentalLogin({super.key});

  @override
  State<ParentalLogin> createState() => _ParentalLoginState();
}

class _ParentalLoginState extends State<ParentalLogin> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String? _errorMessage;
  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.width / 1.1,
                decoration: const BoxDecoration(
                  color: AppColors.primaryColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 220,
                        width: MediaQuery.of(context).size.width / 1.4,
                        child: Image.asset("assets/parentseye_logo.png"),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Welcome to ParentsEye",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Login to your account",
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.poppins(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    _buildTextField(
                      usernameController,
                      "Username",
                      Icons.person,
                    ),
                    const SizedBox(height: 15),
                    _buildTextField(
                      passwordController,
                      "Password",
                      Icons.lock,
                      isPassword: true,
                    ),
                    const SizedBox(height: 25),
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        return Center(
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width / 1.1,
                            child: ElevatedButton(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () => _handleLogin(authProvider),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: authProvider.isLoading
                                  ? LoadingAnimationWidget.flickr(
                                      leftDotColor: Colors.red,
                                      rightDotColor: Colors.blue,
                                      size: 30)
                                  : Text(
                                      'Login',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textColor,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const HelpAndSupportScreen(),
                            ),
                          );
                        },
                        child: Text(
                          "Need Help?",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: AppColors.textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hintText,
    IconData icon, {
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !_isPasswordVisible,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'This field is required';
          }
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                )
              : null,
          hintText: '$hintText *',
          hintStyle: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }

  Future<void> _handleLogin(AuthProvider authProvider) async {
    if (_formKey.currentState!.validate()) {
      String? result = await authProvider.login(
        username: usernameController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (result == null) {
        if (authProvider.loginType == LoginType.parent) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const Dashboard()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DevicesScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage = result;
        });
      }
    }
  }
}
