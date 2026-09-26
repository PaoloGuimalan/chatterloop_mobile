import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Makes picking photos and videos open the phone's GALLERY - Android's
/// photo picker - rather than the file browser.
///
/// image_picker's Android side asks for any file (ACTION_GET_CONTENT) unless
/// told otherwise, and on a Xiaomi that opens the file manager. Called once at
/// startup, so it covers every gallery pick: posts, moments, chat photos,
/// profile pictures. Android 11 and 12 get the picker from Google Play
/// services (see the ModuleDependencies entry in AndroidManifest.xml); where a
/// phone has none at all, Android itself falls back to the file browser.
void useGalleryPicker() {
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
}
