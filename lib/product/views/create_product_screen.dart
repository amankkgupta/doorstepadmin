import 'package:admindoorstep/auth/viewmodels/auth_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateProductScreen extends StatefulWidget {
  const CreateProductScreen({super.key});

  @override
  State<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productNameController = TextEditingController();
  final _productDescriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _mrpController = TextEditingController();
  final _documentsController = TextEditingController();
  final _otherDetailsController = TextEditingController();
  final _productNameHindiController = TextEditingController();
  final _userEmailController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _productNameController.dispose();
    _productDescriptionController.dispose();
    _amountController.dispose();
    _mrpController.dispose();
    _documentsController.dispose();
    _otherDetailsController.dispose();
    _productNameHindiController.dispose();
    _userEmailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final categoryId = context.read<AuthViewModel>().user?.categoryId;
      if (categoryId == null) {
        setState(() {
          _errorMessage = 'Unable to find admin category.';
        });
        return;
      }

      final email = _userEmailController.text.trim();
      dynamic userId;

      if (email.isNotEmpty) {
        final user = await Supabase.instance.client
            .from('users')
            .select('user_id')
            .eq('email', email)
            .maybeSingle();

        if (user == null || user['user_id'] == null) {
          setState(() {
            _errorMessage = 'No user found for this email.';
          });
          return;
        }

        userId = user['user_id'];
      }

      final documents = _documentsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final otherDetails = _otherDetailsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final payload = <String, dynamic>{
        'product_name': _productNameController.text.trim(),
        'product_description': _productDescriptionController.text.trim(),
        'amount': double.parse(_amountController.text.trim()),
        'mrp': double.parse(_mrpController.text.trim()),
        'documents': documents,
        'criteria': otherDetails,
        'product_name_hindi': _productNameHindiController.text.trim(),
        'category_id': categoryId,
      };

      if (userId != null) {
        payload['user_id'] = userId;
      }

      await Supabase.instance.client.from('products').insert(payload);

      setState(() {
        _successMessage = 'Product created successfully.';
      });

      _formKey.currentState!.reset();
      _productNameController.clear();
      _productDescriptionController.clear();
      _amountController.clear();
      _mrpController.clear();
      _documentsController.clear();
      _otherDetailsController.clear();
      _productNameHindiController.clear();
      _userEmailController.clear();
    } on PostgrestException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unable to create product right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Product')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Product',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Fill in the product details and submit to save it in Supabase.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _productNameController,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter product name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _productDescriptionController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Product description',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter product description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Amount'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter amount';
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _mrpController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'MRP'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter MRP';
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return 'Enter a valid MRP';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _documentsController,
                      decoration: const InputDecoration(
                        labelText: 'Documents',
                        hintText: 'doc1, doc2, doc3 (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _otherDetailsController,
                      decoration: const InputDecoration(
                        labelText: 'Other details',
                        hintText: 'detail1, detail2, detail3',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter at least one other detail';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _productNameHindiController,
                      decoration: const InputDecoration(
                        labelText: 'Product name hindi',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter product name in Hindi';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _userEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'User email',
                        hintText: 'Optional',
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    if (_successMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _successMessage!,
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Submit'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
