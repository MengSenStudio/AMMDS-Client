import 'storage.dart';
import 'storage_impl_file.dart';

export 'storage_impl_file.dart';
export 'storage_impl_memory.dart';

/// IO 平台（桌面 / 移动）存储装配：落盘到应用私有目录。
PreferencesStorage createPreferencesStorage() => FilePreferencesStorage();

/// IO 平台（桌面 / 移动）安全存储装配。
SecureStorage createSecureStorage() => FileSecureStorage();
