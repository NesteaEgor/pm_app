import 'package:flutter/material.dart';
import '../../core/ui/glass.dart';
import 'auth_api.dart';

class LoginScreen extends StatefulWidget {
  final AuthApi authApi;
  final VoidCallback onAuthed;

  const LoginScreen({super.key, required this.authApi, required this.onAuthed});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController(text: 'User');
  bool _loading = false;
  String? _error;
  bool _isRegister = false;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isRegister) {
        await widget.authApi.register(
          email: _email.text.trim(),
          password: _pass.text,
          displayName: _name.text.trim().isEmpty ? 'User' : _name.text.trim(),
        );
      } else {
        await widget.authApi.login(
          email: _email.text.trim(),
          password: _pass.text,
        );
      }
      widget.onAuthed();
    } catch (e) {
      setState(() => _error = 'Ошибка. Проверь данные / сервер.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // “жидкий фон” — мягкий градиент + пятна
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                  Color(0xFF0B1220),
                ],
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: _Blob(size: 260),
          ),
          Positioned(
            bottom: -140,
            right: -90,
            child: _Blob(size: 300),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Glass(
                  blur: 22,
                  opacity: 0.16,
                  radius: 28,
                  padding: const EdgeInsets.all(18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          _isRegister ? 'PM • Регистрация' : 'PM • Вход',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_isRegister) ...[
                          TextField(
                            controller: _name,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dec('Имя'),
                          ),
                          const SizedBox(height: 10),
                        ],

                        TextField(
                          controller: _email,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.emailAddress,
                          decoration: _dec('Email'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _pass,
                          style: const TextStyle(color: Colors.white),
                          obscureText: true,
                          decoration: _dec('Пароль'),
                        ),

                        const SizedBox(height: 12),
                        if (_error != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                          ),

                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Text(_loading ? '...' : (_isRegister ? 'Создать аккаунт' : 'Войти')),
                          ),
                        ),

                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                            _isRegister = !_isRegister;
                            _error = null;
                          }),
                          child: Text(
                            _isRegister ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Регистрация',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  const _Blob({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.cyanAccent.withValues(alpha: 0.28),
            Colors.purpleAccent.withValues(alpha: 0.14),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
