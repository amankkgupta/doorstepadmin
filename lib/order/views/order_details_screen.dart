import 'package:admindoorstep/auth/viewmodels/auth_view_model.dart';
import 'package:admindoorstep/download/download_helper.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final dynamic orderId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  static const List<String> _statusOptions = [
    'in_progress',
    'applied',
    'completed',
    'rejected',
    'action_needed',
    'refunded',
  ];

  late dynamic _currentOrderId;
  late Future<Map<String, dynamic>?> _orderFuture;
  List<Map<String, dynamic>> _loadedDocuments = const [];
  bool _isLoadingDocuments = false;
  String? _documentsErrorMessage;
  bool _hasLoadedDocuments = false;
  bool _isLoadingAdjacentOrders = false;
  bool _hasResolvedAdjacentOrders = false;
  dynamic _previousOrderId;
  dynamic _nextOrderId;
  dynamic _loadedCategoryId;
  List<dynamic>? _categoryProductIds;

  @override
  void initState() {
    super.initState();
    _currentOrderId = widget.orderId;
    _orderFuture = _fetchOrder();
  }

  Future<Map<String, dynamic>?> _fetchOrder() async {
    final categoryId = context.read<AuthViewModel>().user?.categoryId;

    var query = Supabase.instance.client
        .from('orders')
        .select(
          'order_id, created_at, message, status, first_document_name, '
          'first_document_url, '
          'second_document_name, second_document_url, phone, support_phone, '
          'is_others, applicant_name, product_name, user_id',
        )
        .eq('order_id', _currentOrderId);

    if (categoryId != null) {
      final productIds = await _fetchProductIdsForCategory(categoryId);
      if (productIds.isEmpty) {
        return null;
      }

      query = query.inFilter('product_id', productIds);
    }

    final response = await query.maybeSingle();

    return response;
  }

  Future<void> _refreshOrder() async {
    setState(() {
      _loadedDocuments = const [];
      _documentsErrorMessage = null;
      _hasLoadedDocuments = false;
      _hasResolvedAdjacentOrders = false;
      _previousOrderId = null;
      _nextOrderId = null;
      _orderFuture = _fetchOrder();
    });
  }

  Future<void> _loadAdjacentOrders(Map<String, dynamic> order) async {
    final createdAtText = order['created_at']?.toString().trim() ?? '';
    final status = order['status']?.toString().trim() ?? '';

    if (createdAtText.isEmpty || status.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previousOrderId = null;
        _nextOrderId = null;
        _hasResolvedAdjacentOrders = true;
      });
      return;
    }

    setState(() {
      _isLoadingAdjacentOrders = true;
    });

    try {
      final categoryId = context.read<AuthViewModel>().user?.categoryId;
      List<dynamic>? productIds;
      if (categoryId != null) {
        productIds = await _fetchProductIdsForCategory(categoryId);

        if (productIds.isEmpty) {
          if (!mounted) {
            return;
          }
          setState(() {
            _previousOrderId = null;
            _nextOrderId = null;
            _hasResolvedAdjacentOrders = true;
          });
          return;
        }
      }

      var previousQuery = Supabase.instance.client
          .from('orders')
          .select('order_id')
          .eq('status', status);

      var nextQuery = Supabase.instance.client
          .from('orders')
          .select('order_id')
          .eq('status', status);

      if (productIds != null) {
        previousQuery = previousQuery.inFilter('product_id', productIds);
        nextQuery = nextQuery.inFilter('product_id', productIds);
      }

      final previousResponse = await previousQuery
          .lt('created_at', createdAtText)
          .order('created_at', ascending: false)
          .limit(1);

      final nextResponse = await nextQuery
          .gt('created_at', createdAtText)
          .order('created_at', ascending: true)
          .limit(1);

      if (!mounted) {
        return;
      }

      final previousOrders = (previousResponse as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final nextOrders = (nextResponse as List<dynamic>)
          .cast<Map<String, dynamic>>();

      setState(() {
        _previousOrderId = previousOrders.isEmpty
            ? null
            : previousOrders.first['order_id'];
        _nextOrderId = nextOrders.isEmpty ? null : nextOrders.first['order_id'];
        _hasResolvedAdjacentOrders = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previousOrderId = null;
        _nextOrderId = null;
        _hasResolvedAdjacentOrders = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdjacentOrders = false;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchProductIdsForCategory(dynamic categoryId) async {
    if (_loadedCategoryId == categoryId && _categoryProductIds != null) {
      return _categoryProductIds!;
    }

    final response = await Supabase.instance.client
        .from('products')
        .select('product_id')
        .eq('category_id', categoryId);

    final productIds = (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((product) => product['product_id'])
        .where((productId) => productId != null)
        .toList();

    _loadedCategoryId = categoryId;
    _categoryProductIds = productIds;
    return productIds;
  }

  Future<void> _goToOrder(dynamic orderId) async {
    if (orderId == null || orderId == _currentOrderId) {
      return;
    }

    setState(() {
      _currentOrderId = orderId;
      _loadedDocuments = const [];
      _documentsErrorMessage = null;
      _hasLoadedDocuments = false;
      _hasResolvedAdjacentOrders = false;
      _previousOrderId = null;
      _nextOrderId = null;
      _orderFuture = _fetchOrder();
    });
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoadingDocuments = true;
      _documentsErrorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('documents')
          .select('vault_document_id(name, value, type)')
          .eq('order_id', _currentOrderId);

      if (!mounted) {
        return;
      }

      final documents = (response as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((document) {
            final vaultDocument = document['vault_document_id'];
            final related = vaultDocument is Map<String, dynamic>
                ? vaultDocument
                : <String, dynamic>{};

            return <String, dynamic>{
              'document_name': related['name'] ?? 'Document',
              'document_value': related['value'],
              'document_type': related['type'] ?? 'text',
            };
          })
          .where((document) => document['document_value'] != null)
          .toList();

      setState(() {
        _loadedDocuments = documents;
        _hasLoadedDocuments = true;
      });
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _documentsErrorMessage = error.message;
        _hasLoadedDocuments = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _documentsErrorMessage = 'Unable to load documents right now.';
        _hasLoadedDocuments = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDocuments = false;
        });
      }
    }
  }

  bool _isUrlValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(text);
    return uri != null && uri.hasScheme;
  }

  String _sanitizeStorageSegment(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  String _contentTypeForFileName(String fileName) {
    final lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }

    return 'application/octet-stream';
  }

  bool _isAllowedDocumentFile(String fileName) {
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.pdf') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp');
  }

  Future<void> _openDocumentValue(dynamic value) async {
    final text = value?.toString().trim() ?? '';
    final uri = Uri.tryParse(text);

    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open document URL')),
    );
  }

  String _buildDownloadFileName(String name, String source) {
    final trimmedName = name.trim();
    final sanitizedName = trimmedName
        .replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_')
        .trim();

    final sourceUri = Uri.tryParse(source);
    final sourcePath = sourceUri?.path ?? source;
    final dotIndex = sourcePath.lastIndexOf('.');
    final extension = dotIndex >= 0 ? sourcePath.substring(dotIndex) : '';

    if (sanitizedName.isEmpty) {
      return extension.isEmpty ? 'document' : 'document$extension';
    }

    if (sanitizedName.contains('.') || extension.isEmpty) {
      return sanitizedName;
    }

    return '$sanitizedName$extension';
  }

  Future<String> _resolveStoredDocumentUrl(String value) async {
    if (_isUrlValue(value)) {
      return value;
    }

    return Supabase.instance.client.storage
        .from('documents')
        .createSignedUrl(value, 60 * 60);
  }

  Future<void> _downloadStoredDocument(
    dynamic value, {
    required String fileName,
  }) async {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    try {
      final resolvedUrl = await _resolveStoredDocumentUrl(text);
      final downloadName = _buildDownloadFileName(fileName, text);
      final didDownload = await downloadFileFromUrl(resolvedUrl, downloadName);

      if (didDownload || !mounted) {
        return;
      }

      await _openDocumentValue(resolvedUrl);
    } on StorageException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open document')));
    }
  }

  Future<void> _showDocumentValuePopup(String name, dynamic value) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(name),
          content: SingleChildScrollView(
            child: SelectableText('${value ?? '-'}'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showChangeMessageDialog(String currentMessage) async {
    final controller = TextEditingController(text: currentMessage);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Message'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          try {
                            await Supabase.instance.client
                                .from('orders')
                                .update({'message': controller.text.trim()})
                                .eq('order_id', _currentOrderId);

                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            await _refreshOrder();
                          } on PostgrestException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                              isSaving = false;
                            });
                          } catch (_) {
                            setDialogState(() {
                              errorMessage = 'Unable to update message.';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showChangeStatusDialog(String currentStatus) async {
    String selectedStatus = currentStatus.isNotEmpty
        ? currentStatus
        : _statusOptions.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Status'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _statusOptions.contains(selectedStatus)
                        ? selectedStatus
                        : _statusOptions.first,
                    items: _statusOptions
                        .map(
                          (status) => DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          ),
                        )
                        .toList(),
                    onChanged: isSaving
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              selectedStatus = value;
                            });
                          },
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          try {
                            await Supabase.instance.client
                                .from('orders')
                                .update({'status': selectedStatus})
                                .eq('order_id', _currentOrderId);

                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            await _refreshOrder();
                          } on PostgrestException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                              isSaving = false;
                            });
                          } catch (_) {
                            setDialogState(() {
                              errorMessage = 'Unable to update status.';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateRequirementDialog(dynamic userId) async {
    final formKey = GlobalKey<FormState>();
    final requirementNameController = TextEditingController();
    final requirementDescController = TextEditingController();
    String selectedType = 'file';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Requirement'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: requirementNameController,
                      decoration: const InputDecoration(
                        labelText: 'Requirement name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter requirement name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: requirementDescController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Requirement desc',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter requirement description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      items: const [
                        DropdownMenuItem(value: 'file', child: Text('file')),
                        DropdownMenuItem(value: 'text', child: Text('text')),
                        DropdownMenuItem(value: 'pay', child: Text('pay')),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setDialogState(() {
                                selectedType = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Requirement type',
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          try {
                            await Supabase.instance.client
                                .from('requirements')
                                .insert({
                                  'requirement_name': requirementNameController
                                      .text
                                      .trim(),
                                  'requirement_desc': requirementDescController
                                      .text
                                      .trim(),
                                  'requirement_type': selectedType,
                                  'user_id': userId,
                                  'order_id': _currentOrderId,
                                });

                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Requirement created successfully',
                                ),
                              ),
                            );
                          } on PostgrestException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                              isSaving = false;
                            });
                          } catch (_) {
                            setDialogState(() {
                              errorMessage = 'Unable to create requirement.';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    requirementNameController.dispose();
    requirementDescController.dispose();
  }

  Future<void> _showSendNotificationDialog(dynamic userId) async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final launchUrlController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Send Notification'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Notification Title',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter notification title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: launchUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Launch URL (Optional)',
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          try {
                            final userIdValue = userId?.toString().trim() ?? '';
                            final titleText = titleController.text.trim();
                            final launchUrlText = launchUrlController.text
                                .trim();

                            // 1. Insert into notifications
                            await Supabase.instance.client
                                .from('notifications')
                                .insert({
                                  'user_id': userIdValue,
                                  'content': titleText,
                                  'launch_url': launchUrlText,
                                });

                            // 2. Fetch FCM token and unread_count
                            final fcmData = await Supabase.instance.client
                                .from('fcmtokens')
                                .select('fcmtoken, unread_count')
                                .eq('user_id', userIdValue)
                                .maybeSingle();

                            if (fcmData != null &&
                                fcmData['fcmtoken'] != null) {
                              final token = fcmData['fcmtoken'];
                              final unreadCount =
                                  (fcmData['unread_count'] as num?)?.toInt() ??
                                  0;

                              // 3. Update unread_count
                              await Supabase.instance.client
                                  .from('fcmtokens')
                                  .update({'unread_count': unreadCount + 1})
                                  .eq('user_id', userIdValue);

                              // 4. Send FCM Push Notification via Edge Function
                              // Fire and forget, as it's okay if FCM fails
                              Supabase.instance.client.functions
                                  .invoke(
                                    'send-notification',
                                    body: {
                                      'token': token,
                                      'title': titleText,
                                      'launch_url': launchUrlText,
                                    },
                                  )
                                  .catchError((e) {
                                    debugPrint('FCM sending failed: $e');
                                    return e;
                                  });
                            }

                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notification sent successfully'),
                              ),
                            );
                          } catch (e) {
                            debugPrint('Error sending notification: $e');
                            setDialogState(() {
                              errorMessage = 'Unable to send notification.';
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    launchUrlController.dispose();
  }

  Future<void> _showWhatsAppDialog(
    String? phone,
    String? applicantName,
    String? productName,
    String? status,
  ) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Phone number is missing.')));
      return;
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    Future<void> openWhatsApp(String text) async {
      final uri = Uri.parse(
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(text)}',
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    }

    final requirementController = TextEditingController();
    final customController = TextEditingController();

    final safeApplicantName = applicantName?.trim() ?? 'Customer';
    final safeProductName = productName?.trim() ?? 'Product';
    final safeStatus = status?.trim() ?? 'In Progress';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Send WhatsApp Message'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () {
                      final msg =
                          '''Namaste $safeApplicantName 👋

Aapke *$safeProductName* ka status update:

📌 Status: *$safeStatus*  
Aapki application safalta se process ho chuki hai.

Doorsy App par aap apni request ka poora progress track kar sakte hain, aur sabhi updates ek hi jagah par dekh sakte hain.

Kisi bhi madad ke liye aap humein app ke through contact kar sakte hain.

Dhanyavaad 😊  
Team Doorsy''';
                      openWhatsApp(msg);
                    },
                    child: const Text('Send Update'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  TextFormField(
                    controller: requirementController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Requirement Details',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      final reqText = requirementController.text.trim();
                      if (reqText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter requirement details.'),
                          ),
                        );
                        return;
                      }

                      final msg =
                          '''Namaste $safeApplicantName 👋

Aapke *$safeProductName* ki process aage badhane ke liye kuch additional details/documents chahiye.

Kripya neeche di gayi requirements **Doorsy App ke Requests Section** me upload/share karein:

$reqText

⚠️ Sabhi details sirf **Doorsy App** ke through hi share karein.

OTP verification ke liye available rahein.

Dhanyavaad 😊  
Team Doorsy''';
                      openWhatsApp(msg);
                    },
                    child: const Text('Send Requirement'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  TextFormField(
                    controller: customController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Custom Message',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      final text = customController.text.trim();
                      if (text.isEmpty) return;
                      openWhatsApp(text);
                    },
                    child: const Text('Send Custom Message'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );

    requirementController.dispose();
    customController.dispose();
  }

  Future<void> _showUploadDocumentDialog({
    required dynamic userId,
    required String title,
    required String successMessage,
    required String failureMessage,
    required String documentNameColumn,
    required String documentUrlColumn,
  }) async {
    final formKey = GlobalKey<FormState>();
    final documentNameController = TextEditingController();
    PlatformFile? selectedFile;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: documentNameController,
                      decoration: const InputDecoration(
                        labelText: 'Document name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter document name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final result = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: const [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                      'webp',
                                    ],
                                    withData: true,
                                  );

                              if (result == null || result.files.isEmpty) {
                                return;
                              }

                              setDialogState(() {
                                if (!_isAllowedDocumentFile(
                                  result.files.single.name,
                                )) {
                                  errorMessage =
                                      'Only PDF and image files are allowed';
                                  return;
                                }
                                selectedFile = result.files.single;
                                errorMessage = null;
                                if (documentNameController.text
                                    .trim()
                                    .isEmpty) {
                                  documentNameController.text =
                                      selectedFile!.name;
                                }
                              });
                            },
                      child: const Text('Choose file'),
                    ),
                    if (selectedFile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected file: ${selectedFile!.name}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);

                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          if (selectedFile == null) {
                            setDialogState(() {
                              errorMessage = 'Choose a file first';
                            });
                            return;
                          }

                          if (!_isAllowedDocumentFile(selectedFile!.name)) {
                            setDialogState(() {
                              errorMessage =
                                  'Only PDF and image files are allowed';
                            });
                            return;
                          }

                          final Uint8List? bytes = selectedFile!.bytes;
                          if (bytes == null) {
                            setDialogState(() {
                              errorMessage = 'Unable to read selected file';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          try {
                            final userIdValue = userId?.toString().trim() ?? '';
                            if (userIdValue.isEmpty) {
                              setDialogState(() {
                                errorMessage = 'Order user_id is missing';
                                isSaving = false;
                              });
                              return;
                            }

                            final sanitizedFolder = _sanitizeStorageSegment(
                              userIdValue,
                            );
                            final sanitizedName = _sanitizeStorageSegment(
                              selectedFile!.name,
                            );
                            final filePath =
                                '$sanitizedFolder/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

                            await Supabase.instance.client.storage
                                .from('documents')
                                .uploadBinary(
                                  filePath,
                                  bytes,
                                  fileOptions: FileOptions(
                                    contentType: _contentTypeForFileName(
                                      selectedFile!.name,
                                    ),
                                  ),
                                );

                            await Supabase.instance.client
                                .from('orders')
                                .update({
                                  documentNameColumn: documentNameController
                                      .text
                                      .trim(),
                                  documentUrlColumn: filePath,
                                })
                                .eq('order_id', _currentOrderId);

                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop();
                            await _refreshOrder();
                            messenger.showSnackBar(
                              SnackBar(content: Text(successMessage)),
                            );
                          } on StorageException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                              isSaving = false;
                            });
                          } on PostgrestException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                              isSaving = false;
                            });
                          } catch (_) {
                            setDialogState(() {
                              errorMessage = failureMessage;
                              isSaving = false;
                            });
                          }
                        },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    documentNameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _orderFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Unable to load order details right now.'),
              ),
            );
          }

          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('Order not found.'));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isLoadingAdjacentOrders) {
              return;
            }
            if (_hasResolvedAdjacentOrders) {
              return;
            }
            _loadAdjacentOrders(order);
          });

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${order['product_name'] ?? '-'}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _previousOrderId == null
                        ? null
                        : () => _goToOrder(_previousOrderId),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Previous'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _nextOrderId == null
                        ? null
                        : () => _goToOrder(_nextOrderId),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Next'),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  if (_isLoadingAdjacentOrders) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionButton(
                    label: 'Create requirements',
                    onPressed: () =>
                        _showCreateRequirementDialog(order['user_id']),
                  ),
                  _ActionButton(
                    label: 'Change Message',
                    onPressed: () =>
                        _showChangeMessageDialog('${order['message'] ?? ''}'),
                  ),
                  _ActionButton(
                    label: 'Change Status',
                    onPressed: () =>
                        _showChangeStatusDialog('${order['status'] ?? ''}'),
                  ),
                  _ActionButton(
                    label: 'Load document',
                    onPressed: _loadDocuments,
                  ),
                  _ActionButton(
                    label: 'Upload first document',
                    onPressed: () => _showUploadDocumentDialog(
                      userId: order['user_id'],
                      title: 'Upload First Document',
                      successMessage: 'First document uploaded successfully',
                      failureMessage: 'Unable to upload first document.',
                      documentNameColumn: 'first_document_name',
                      documentUrlColumn: 'first_document_url',
                    ),
                  ),
                  _ActionButton(
                    label: 'Upload second document',
                    onPressed: () => _showUploadDocumentDialog(
                      userId: order['user_id'],
                      title: 'Upload Second Document',
                      successMessage: 'Second document uploaded successfully',
                      failureMessage: 'Unable to upload second document.',
                      documentNameColumn: 'second_document_name',
                      documentUrlColumn: 'second_document_url',
                    ),
                  ),
                  _ActionButton(
                    label: 'Send Notification',
                    onPressed: () =>
                        _showSendNotificationDialog(order['user_id']),
                  ),
                  _ActionButton(
                    label: 'Send WhatsApp',
                    onPressed: () => _showWhatsAppDialog(
                      order['phone']?.toString(),
                      order['applicant_name']?.toString(),
                      order['product_name']?.toString(),
                      order['status']?.toString(),
                    ),
                  ),
                ],
              ),
              if (_isLoadingDocuments) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ] else if (_documentsErrorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _documentsErrorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ] else if (_hasLoadedDocuments) ...[
                const SizedBox(height: 16),
                _DetailCard(
                  title: 'Loaded Documents',
                  children: _loadedDocuments.isEmpty
                      ? const [Text('No matching documents found.')]
                      : [
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _loadedDocuments
                                .map(
                                  (document) => _LoadedDocumentItem(
                                    name:
                                        '${document['document_name'] ?? 'Document'}',
                                    value: document['document_value'],
                                    isFile:
                                        '${document['document_type'] ?? ''}'
                                            .trim()
                                            .toLowerCase() ==
                                        'file',
                                    onOpen: () => _downloadStoredDocument(
                                      document['document_value'],
                                      fileName:
                                          '${document['document_name'] ?? 'Document'}',
                                    ),
                                    onShowValue: () => _showDocumentValuePopup(
                                      '${document['document_name'] ?? 'Document'}',
                                      document['document_value'],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                ),
              ],
              const SizedBox(height: 24),
              _DetailCard(
                children: [
                  _DetailRow(
                    label: 'Applicant Name',
                    value: order['applicant_name'],
                  ),
                  _DetailRow(label: 'Status', value: order['status']),
                  _DetailRow(label: 'Message', value: order['message']),
                  _DetailRow(label: 'Phone', value: order['phone']),
                  _DetailRow(
                    label: 'Support Phone',
                    value: order['support_phone'],
                  ),
                  _DetailRow(label: 'Is Others', value: order['is_others']),
                  _DetailRow(label: 'User ID', value: order['user_id']),
                ],
              ),
              const SizedBox(height: 16),
              _DetailCard(
                title: 'Documents',
                children: [
                  _DownloadRow(
                    label:
                        '${order['first_document_name'] ?? 'First Document'}',
                    hasValue: (order['first_document_url'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty,
                    onPressed: () => _downloadStoredDocument(
                      order['first_document_url'],
                      fileName: '${order['first_document_name'] ?? 'Document'}',
                    ),
                  ),
                  _DownloadRow(
                    label:
                        '${order['second_document_name'] ?? 'Second Document'}',
                    hasValue: (order['second_document_url'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty,
                    onPressed: () => _downloadStoredDocument(
                      order['second_document_url'],
                      fileName:
                          '${order['second_document_name'] ?? 'Document'}',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadedDocumentItem extends StatelessWidget {
  const _LoadedDocumentItem({
    required this.name,
    required this.value,
    required this.isFile,
    required this.onOpen,
    required this.onShowValue,
  });

  final String name;
  final dynamic value;
  final bool isFile;
  final VoidCallback onOpen;
  final VoidCallback onShowValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: isFile
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onOpen,
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'Download document',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                InkWell(onTap: onShowValue, child: Text('${value ?? '-'}')),
              ],
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onPressed ?? () {}, child: Text(label));
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text('${value ?? '-'}'),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.label,
    required this.hasValue,
    required this.onPressed,
  });

  final String label;
  final bool hasValue;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (hasValue)
            IconButton(
              onPressed: onPressed,
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download document',
            )
          else
            const Text('-'),
        ],
      ),
    );
  }
}
