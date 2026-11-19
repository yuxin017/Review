import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data/admin_attraction_store.dart';
import 'data/attraction_training_store.dart';
import 'attraction_map_picker.dart';
import 'attraction_editor_section.dart';
import 'attraction_number_field.dart';
import 'park_category_widgets.dart';
import 'data/park_category_repository.dart';
import '../../attractions/models/attraction.dart';
import '../../attractions/widgets/attraction_widgets.dart';
import '../portal/admin_theme.dart';
import 'attraction_admin_guard.dart';
import '../../attractions/widgets/attraction_cover.dart';
import 'cover_photo.dart';
import '../../attractions/data/slot_reader.dart';

class AttractionEditorPage extends StatefulWidget {
  const AttractionEditorPage({
    super.key,
    required this.store,
    required this.adminAccess,
    this.attraction,
    this.kind = ParkPlaceKind.attractions,
    this.pickCover,
    this.slotReader,
    this.categoryRepository,
  });
  final AdminAttractionStore store;
  final ValueListenable<bool> adminAccess;
  final Attraction? attraction;
  final ParkPlaceKind kind;
  final Future<Uint8List?> Function()? pickCover;
  final SlotReader? slotReader;
  final ParkCategoryRepository? categoryRepository;

  @override
  State<AttractionEditorPage> createState() => _AttractionEditorPageState();
}

class _AttractionEditorPageState extends State<AttractionEditorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _trainingTitle = TextEditingController();
  final _duration = TextEditingController();
  final _riders = TextEditingController();
  final _safetyNotes = TextEditingController();
  final _description = TextEditingController();
  final _standby = TextEditingController();
  final _photoField = GlobalKey<FormFieldState<String>>();
  final _height = TextEditingController();
  final _capacity = TextEditingController();
  final _mapX = TextEditingController();
  final _mapY = TextEditingController();
  late final String _id;
  Attraction? _original;
  String? _category;
  String? _categoryId;
  AttractionStatus _status = AttractionStatus.closed;
  bool _saving = false;
  bool _reloading = false;
  String? _error;
  String? _cover;
  AttractionCrowd? _crowd;
  bool _pickingPhoto = false;
  ParkPlaceKind get _kind => _original?.placeKind ?? widget.kind;
  bool get _isRide => _kind == ParkPlaceKind.attractions;
  String get _itemName => _kind.itemName;

  @override
  void initState() {
    super.initState();
    _original = widget.attraction;
    _id = _original?.id ?? widget.store.newAttractionId();
    _fill(_original);
  }

  void _fill(Attraction? attraction) {
    _name.text = attraction?.name ?? '';
    _description.text = attraction?.description ?? '';
    _standby.text = attraction?.standbyMinutes?.toString() ?? '';
    _duration.text = attraction?.rideDurationMinutes?.toString() ?? '';
    _riders.text = attraction?.ridersPerCycle?.toString() ?? '';
    _safetyNotes.text = attraction?.safetyNotes ?? '';
    _cover = attraction?.coverImageBase64;
    _photoField.currentState?.didChange(_cover);
    _crowd = attraction?.crowdLevel;
    _height.text = attraction?.minHeightCm.toString() ?? '0';
    _capacity.text =
        (attraction?.reservationCapacity ??
                Attraction.defaultReservationCapacity)
            .toString();
    _mapX.text = attraction?.mapX.toString() ?? '';
    _mapY.text = attraction?.mapY.toString() ?? '';
    _category = attraction?.category;
    _categoryId = attraction?.categoryId;
    _status = attraction?.status ?? AttractionStatus.closed;
  }

  @override
  void dispose() {
    _name.dispose();
    _trainingTitle.dispose();
    _duration.dispose();
    _riders.dispose();
    _safetyNotes.dispose();
    _description.dispose();
    _standby.dispose();
    _height.dispose();
    _capacity.dispose();
    _mapX.dispose();
    _mapY.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_saving || _pickingPhoto || !widget.adminAccess.value) return;
    setState(() {
      _pickingPhoto = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickCover != null) {
        bytes = await widget.pickCover!();
      } else {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        bytes = await photo?.readAsBytes();
      }
      if (bytes == null) return;
      final encoded = encodeAttractionCover(bytes);
      if (!mounted) return;
      setState(() => _cover = encoded);
      _photoField.currentState?.didChange(encoded);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to select this photo. Please choose another.',
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _pickingPhoto || _reloading || !widget.adminAccess.value) {
      return;
    }
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted fields above.');
      return;
    }
    if (_category == null || _category!.trim().isEmpty ||
        (widget.categoryRepository != null &&
            (_categoryId == null || _categoryId!.trim().isEmpty))) {
      setState(() => _error = 'Choose a category.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final replacement = Attraction(
        id: _id,
        name: _name.text,
        category: _category!,
        categoryId: _categoryId,
        placeKind: _kind,
        status: _status,
        minHeightCm: int.parse(_height.text.trim()),
        reservationCapacity: int.parse(_capacity.text.trim()),
        rideDurationMinutes: _isRide && _duration.text.trim().isNotEmpty
            ? int.parse(_duration.text.trim()) : null,
        ridersPerCycle: _isRide && _riders.text.trim().isNotEmpty
            ? int.parse(_riders.text.trim()) : null,
        safetyNotes: _isRide && _safetyNotes.text.trim().isNotEmpty
            ? _safetyNotes.text.trim() : null,
        mapX: double.parse(_mapX.text.trim()),
        mapY: double.parse(_mapY.text.trim()),
        description: _description.text,
        coverImageBase64: _cover,
        crowdLevel: _crowd,
        standbyMinutes: int.tryParse(_standby.text.trim()),
      );
      if (_original == null) {
        if (_isRide) {
          final store = widget.store;
          if (store is! AttractionTrainingStore) {
            throw StateError('Training is unavailable.');
          }
          final selectedTitle = _trainingTitle.text.trim();
          final courseTitle = selectedTitle.isEmpty
              ? AttractionTrainingPolicy.defaultTitle(_name.text)
              : selectedTitle;
          await (store as AttractionTrainingStore).createAttractionWithTraining(
            replacement,
            courseTitle: courseTitle,
          );
        } else {
          await widget.store.createAttraction(replacement);
        }
      } else {
        await widget.store.updateAttraction(
          original: _original!,
          replacement: replacement,
        );
      }
      if (!mounted) return;
      // Release PopScope before returning from the editor.
      setState(() => _saving = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.adminAccess.value) {
          Navigator.of(context).pop(true);
        }
      });
    } on AttractionConflict catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } on FormatException catch (_) {
      if (mounted) setState(() => _error = 'Check the entered numbers and location.');
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString() ?? 'Check your details.');
    } on FirebaseException catch (error, stackTrace) {
      // Console diagnostics for admins; no technical codes in the form.
      debugPrint('Park Facilities save: ${error.plugin}/${error.code}');
      if (kDebugMode) {
        debugPrint('Attraction save failed: ${error.plugin}/${error.code}');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'permission-denied' =>
              'Save blocked. Check your admin access.',
            'unauthenticated' =>
              'Please sign in again.',
            'unavailable' || 'deadline-exceeded' =>
              'Connection failed. Try again.',
            _ =>
              "Couldn't save changes. Try again.",
          },
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Unexpected attraction save error (${error.runtimeType}): $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        setState(
          () => _error =
              "Couldn't save changes. Try again.",
        );
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  Future<void> _createCourseForExistingRide() async {
    if (_saving || _original == null || !widget.adminAccess.value ||
        widget.store is! AttractionTrainingStore) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.store as AttractionTrainingStore)
          .addRequiredTrainingToExistingRide(
        _id,
        courseTitle: AttractionTrainingPolicy.defaultTitle(_original!.name),
      );
    } on AttractionConflict catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString() ?? 'Check the course name.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't add training. Try again.");
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _reloading || _pickingPhoto;
    final itemHeading =
        '${_itemName[0].toUpperCase()}${_itemName.substring(1)}';
    return AttractionAdminGuard(
      access: widget.adminAccess,
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          backgroundColor: AdminTheme.background,
          appBar: AppBar(
            title: Text(
              _original == null ? 'Add $_itemName' : 'Edit $_itemName',
            ),
            backgroundColor: AdminTheme.background,
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    const SizedBox(height: 2),
                    AttractionEditorSection(
                      title: _isRide ? 'Attraction details' : '${facilityTypeLabel(_kind)} details',
                      description: 'The details visitors see on the park map.',
                      icon: Icons.local_activity_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, layout) {
                              final wide = layout.maxWidth >= 630;
                              final info = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _name,
                                    enabled: !busy,
                                    maxLength: 80,
                                    autovalidateMode: AutovalidateMode.onUserInteraction,
                                    decoration: InputDecoration(
                                      labelText: '$itemHeading name *',
                                      hintText: _isRide ? 'e.g. Ferris Wheel' : 'e.g. Pasta Corner',
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) return 'Enter a name.';
                                      if (text.length < 2 ||
                                          !RegExp(r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF]').hasMatch(text)) {
                                        return 'Enter a valid name.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  ParkCategoryPicker(
                                    kind: _kind,
                                    repository: widget.categoryRepository,
                                    selectedId: _categoryId,
                                    selectedName: _category,
                                    enabled: !busy,
                                    onSelected: (category) => setState(() {
                                      _categoryId = category.id;
                                      _category = category.name;
                                    }),
                                  ),
                                ],
                              );
                              final cover = FormField<String>(
                                key: _photoField,
                                initialValue: _cover,
                                validator: (value) =>
                                    _isRide && _original == null && (value == null || value.isEmpty)
                                        ? 'Add a cover photo.' : null,
                                builder: (field) => Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: field.hasError
                                        ? Theme.of(context).colorScheme.error : AdminTheme.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        AttractionCover(encoded: _cover, width: 94, height: 94),
                                        const SizedBox(width: 10),
                                        Expanded(child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Cover photo',
                                              style: TextStyle(fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 7),
                                            OutlinedButton.icon(
                                              onPressed: busy ? null : _pickPhoto,
                                              icon: const Icon(Icons.photo_outlined, size: 17),
                                              label: Text(_pickingPhoto
                                                  ? 'Uploading...' : _cover == null ? 'Add photo' : 'Change'),
                                            ),
                                          ],
                                        )),
                                      ]),
                                      if (field.hasError) Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(field.errorText!,
                                          style: TextStyle(color: Theme.of(context).colorScheme.error,
                                              fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              return Column(children: [
                                if (wide)
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Expanded(child: info),
                                    const SizedBox(width: 12),
                                    Expanded(child: cover),
                                  ])
                                else ...[
                                  info,
                                  const SizedBox(height: 10),
                                  cover,
                                ],
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _description,
                                  enabled: !busy,
                                  minLines: 2,
                                  maxLines: 3,
                                  maxLength: 1200,
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  decoration: const InputDecoration(
                                    labelText: 'Description *',
                                    hintText: 'What can guests expect?',
                                    alignLabelWithHint: true,
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (text.isEmpty) return 'Enter a description.';
                                    if (text.length < 10) return 'Add at least 10 characters.';
                                    return null;
                                  },
                                ),
                              ]);
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_isRide) ...[
                      const SizedBox(height: 14),
                      AttractionEditorSection(
                        title: 'Ride operations & safety',
                        description: 'Required operating limits and booking capacity.',
                        icon: Icons.tune_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(builder: (context, constraints) {
                              final fieldWidth = constraints.maxWidth >= 560
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth;
                              return Wrap(spacing: 12, runSpacing: 12, children: [
                                SizedBox(width: fieldWidth, child: AttractionNumberField(
                                  controller: _height, label: 'Minimum height (cm)',
                                  min: 0, max: 250, enabled: !busy,
                                )),
                                SizedBox(width: fieldWidth, child: AttractionNumberField(
                                  controller: _duration, label: 'Ride duration (min)',
                                  min: 1, max: 120,
                                  optional: _original != null, enabled: !busy,
                                )),
                                SizedBox(width: fieldWidth, child: AttractionNumberField(
                                  controller: _riders, label: 'Riders per cycle',
                                  min: 1, max: 1000,
                                  optional: _original != null, enabled: !busy,
                                )),
                                SizedBox(width: fieldWidth, child: AttractionNumberField(
                                  controller: _capacity, label: 'Bookings per 15 min',
                                  min: 1, max: 1000, enabled: !busy,
                                )),
                              ]);
                            }),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _safetyNotes,
                              enabled: !busy,
                              minLines: 2,
                              maxLines: 3,
                              maxLength: 500,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              decoration: const InputDecoration(
                                labelText: 'Guest safety instructions *',
                                hintText: 'e.g. Remain seated until the ride stops.',
                                alignLabelWithHint: true,
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (_original == null && text.isEmpty) {
                                  return 'Enter safety instructions.';
                                }
                                if (text.isNotEmpty && text.length < 10) {
                                  return 'Add at least 10 characters.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_isRide) ...[
                      const SizedBox(height: 14),
                      AttractionEditorSection(
                        title: 'Operator training',
                        description: 'Required for staff assigned to this ride.',
                        icon: Icons.school_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_original == null) ...[
                              TextFormField(
                                controller: _trainingTitle,
                                enabled: !busy,
                                maxLength: 120,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                decoration: const InputDecoration(
                                  labelText: 'Training course name (optional)',
                                  hintText: 'Leave blank to use the attraction name',
                                ),
                                validator: (value) => (value ?? '').trim().isEmpty
                                    ? null
                                    : AttractionTrainingPolicy.validateTitle(value),
                              ),
                              const Text(
                                'A matching operator course is created when you save.',
                                style: TextStyle(fontSize: 12, color: AdminTheme.muted),
                              ),
                            ] else if (widget.store is AttractionTrainingStore)
                              StreamBuilder<List<String>>(
                                stream: (widget.store as AttractionTrainingStore)
                                    .watchRequiredTraining(_id),
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return const Text('Could not load training courses.');
                                  }
                                  if (!snapshot.hasData) {
                                    return const LinearProgressIndicator();
                                  }
                                  final titles = snapshot.data!;
                                  if (titles.isEmpty) {
                                    return Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        onPressed: busy ? null : _createCourseForExistingRide,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create required training'),
                                      ),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (final title in titles)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(children: [
                                            const Icon(Icons.check_circle_outline,
                                                color: Color(0xFF27734F), size: 18),
                                            const SizedBox(width: 9),
                                            Expanded(child: Text(title)),
                                          ]),
                                        ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    AttractionEditorSection(
                      title: 'Park location',
                      description: 'Tap the campus map to position this place.',
                      icon: Icons.location_on_outlined,
                      child: FormField<Offset>(
                        initialValue: _mapX.text.isNotEmpty && _mapY.text.isNotEmpty &&
                                (double.tryParse(_mapX.text) ?? -1) >= 0 &&
                                (double.tryParse(_mapX.text) ?? 2) <= 1 &&
                                (double.tryParse(_mapY.text) ?? -1) >= 0 &&
                                (double.tryParse(_mapY.text) ?? 2) <= 1
                            ? Offset(double.parse(_mapX.text), double.parse(_mapY.text))
                            : null,
                        validator: (value) => value == null
                            ? 'Choose a location on the map.' : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StreamBuilder<List<Attraction>>(
                              stream: widget.store.watchAttractions(),
                              builder: (context, snapshot) => AttractionMapPicker(
                                position: field.value,
                                places: snapshot.data ?? const [],
                                excludeId: _id,
                                onChanged: busy ? null : (point) {
                                  field.didChange(point);
                                  _mapX.text = point.dx.toStringAsFixed(6);
                                  _mapY.text = point.dy.toStringAsFixed(6);
                                },
                              ),
                            ),
                            if (field.hasError) Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Text(field.errorText!,
                                style: const TextStyle(color: Color(0xFFB42318), fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_original != null) ...[
                      const SizedBox(height: 22),
                      AttractionEditorSection(
                        title: 'Availability',
                        description: 'Change status to control visitor visibility.',
                        icon: Icons.toggle_on_outlined,
                        child:
                    DropdownButtonFormField<AttractionStatus>(
                      isExpanded: true,
                      key: ValueKey('editor-status-${_status.name}'),
                      initialValue: _status,
                      decoration: InputDecoration(
                        labelText: _isRide ? 'Ride status' : 'Status',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final status in AttractionStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(attractionStatusLabel(status)),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _status = value!),
                    ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3F1),
                          border: Border.all(color: const Color(0xFFEDC5C0)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Color(0xFFAD474A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: const TextStyle(
                            color: Color(0xFF90393C), fontSize: 13))),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: busy ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AdminTheme.rose,
                            minimumSize: const Size(170, 46),
                          ),
                          icon: busy
                              ? const SizedBox(width: 17, height: 17,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : _reloading
                              ? 'Loading...' : 'Save $_itemName'),
                        ),
                      ],
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
