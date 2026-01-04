import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/webdav/test_webdav.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';

/// 偏好设置备份文件名
const String _prefsBackupFileName = 'anx_shared_prefs.json';

/// 同步设置页面组件
/// 负责管理WebDAV同步配置、数据导出/导入等功能
class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

/// SyncSetting页面的状态管理类
/// 处理同步配置、数据导出导入的具体逻辑
class _SyncSettingState extends ConsumerState<SyncSetting> {
  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            // WebDAV开关
            webdavSwitch(context, setState, ref),
            // WebDAV设置项
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                    'Not set'),
                onPressed: (context) async {
                  showWebdavDialog(context);
                }),
            // 立即同步按钮
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                enabled: Prefs().webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            // 仅WiFi下同步开关
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().onlySyncWhenWifi = value;
                  });
                }),
            // 同步完成通知开关
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            // 自动同步开关
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            // 恢复备份
            SettingsTile.navigation(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            // 数据导出
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  exportData(context);
                }),
            // 数据导入
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  /// 显示数据处理对话框（用于导出/导入过程中）
  /// @param title 对话框标题
  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  /// 导出应用数据到ZIP文件
  /// @param context 上下文
  Future<void> exportData(BuildContext context) async {
    AnxLog.info('exportData: start');
    if (!mounted) return;

    // 显示导出进度对话框
    _showDataDialog(L10n.of(context).exporting);

    // 创建偏好设置备份文件
    final File prefsBackupFile = await _createPrefsBackupFile();

    // 使用compute创建ZIP文件（避免UI阻塞）
    RootIsolateToken token = RootIsolateToken.instance!;
    final zipPath = await compute(createZipFile, {
      'token': token,
      'prefsBackupFilePath': prefsBackupFile.path,
    });

    final file = File(zipPath);
    SmartDialog.dismiss();

    if (await file.exists()) {
      // 生成备份文件名（包含日期）
      String fileName =
          'AnxReader-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v3.zip';

      // 保存文件到下载目录
      String? filePath = await saveFileToDownload(
          sourceFilePath: file.path,
          fileName: fileName,
          mimeType: 'application/zip');

      // 删除临时ZIP文件
      await file.delete();

      // 显示导出结果提示
      if (filePath != null) {
        AnxLog.info('exportData: Saved to: $filePath');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).exportTo(filePath));
      } else {
        AnxLog.info('exportData: Cancelled');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
      }
    }
  }

  /// 从ZIP文件导入应用数据
  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (!mounted) return;

    // 选择ZIP文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null) {
      return;
    }

    String? filePath = result.files.single.path;
    if (filePath == null) {
      AnxLog.info('importData: cannot get file path');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    File zipFile = File(filePath);
    if (!await zipFile.exists()) {
      AnxLog.info('importData: zip file not found');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    // 显示导入进度对话框
    _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);

    String pathSeparator = Platform.pathSeparator;

    // 创建临时目录用于解压
    Directory cacheDir = await getAnxTempDir();
    String cachePath = cacheDir.path;
    String extractPath = '$cachePath${pathSeparator}anx_reader_import';

    try {
      await Directory(extractPath).create(recursive: true);

      // 使用compute解压ZIP文件（避免UI阻塞）
      await compute(extractZipFile, {
        'zipFilePath': zipFile.path,
        'destinationPath': extractPath,
      });

      // 复制各种资源文件
      String docPath = await getAnxDocumentsPath();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}file'),
          getFileDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}cover'),
          getCoverDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}font'),
          getFontDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}bgimg'),
          getBgimgDir(path: docPath));

      // 复制数据库文件
      DBHelper.close();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}databases'),
          await getAnxDataBasesDir());
      DBHelper().initDB();

      // 恢复偏好设置
      await _restorePrefsFromBackup(extractPath);

      // 显示导入成功提示
      AnxLog.info('importData: import success');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
    } catch (e) {
      // 显示导入失败提示
      AnxLog.info('importData: error while unzipping or copying files: $e');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
    } finally {
      // 关闭对话框并清理临时文件
      SmartDialog.dismiss();
      await Directory(extractPath).delete(recursive: true);
    }
  }

  /// 同步复制目录（包括子目录和文件）
  /// @param source 源目录
  /// @param destination 目标目录
  void _copyDirectorySync(Directory source, Directory destination) {
    if (!source.existsSync()) {
      return;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    destination.createSync(recursive: true);
    source.listSync(recursive: false).forEach((entity) {
      final newPath = destination.path +
          Platform.pathSeparator +
          path.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory(newPath));
      }
    });
  }
}

/// 创建备份ZIP文件（在后台线程执行）
/// @param params 参数映射，包含token和偏好设置备份文件路径
/// @return ZIP文件路径
Future<String> createZipFile(Map<String, dynamic> params) async {
  RootIsolateToken token = params['token'];
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final File prefsBackupFile = File(prefsBackupFilePath);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  // 生成ZIP文件名
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getAnxTempDir()).path}/AnxReader-Backup-$date.zip';

  // 获取需要备份的目录和文件
  final docPath = await getAnxDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath), // 文件目录
    getCoverDir(path: docPath), // 封面目录
    getFontDir(path: docPath), // 字体目录
    getBgimgDir(path: docPath), // 背景图片目录
    await getAnxDataBasesDir(), // 数据库目录
    prefsBackupFile, // 偏好设置备份文件
  ];

  AnxLog.info('exportData: directoryList: $directoryList');

  // 创建ZIP文件并添加内容
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  for (final dir in directoryList) {
    if (dir is Directory) {
      await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }
  encoder.close();

  // 删除临时的偏好设置备份文件
  if (await prefsBackupFile.exists()) {
    await prefsBackupFile.delete();
  }

  return zipPath;
}

/// 解压ZIP文件（在后台线程执行）
/// @param params 参数映射，包含ZIP文件路径和目标解压路径
Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    // 解码ZIP文件
    final archive = ZipDecoder().decodeBuffer(input);
    // 解压到目标路径
    extractArchiveToDiskSync(archive, destinationPath);
    // 清理资源
    archive.clearSync();
  } finally {
    // 关闭文件流
    await input.close();
  }
}

/// 创建偏好设置备份文件
/// @return 备份文件对象
Future<File> _createPrefsBackupFile() async {
  final Directory tempDir = await getAnxTempDir();
  final File backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  // 构建偏好设置备份映射
  final Map<String, dynamic> prefsMap = await Prefs().buildPrefsBackupMap();
  // 写入文件
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

/// 从备份文件恢复偏好设置
/// @param extractPath 解压路径
/// @return 是否恢复成功
Future<bool> _restorePrefsFromBackup(String extractPath) async {
  final File backupFile = File('$extractPath/$_prefsBackupFileName');
  if (!await backupFile.exists()) {
    return false;
  }
  try {
    // 读取并解析备份文件
    final dynamic decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is Map<String, dynamic>) {
      // 应用备份的偏好设置
      await Prefs().applyPrefsBackupMap(decoded);
      return true;
    }
    AnxLog.info('importData: prefs backup has unexpected format');
  } catch (e) {
    AnxLog.info('importData: failed to restore prefs backup: $e');
  }
  return false;
}

/// 显示WebDAV设置对话框
/// @param context 上下文
void showWebdavDialog(BuildContext context) {
  final title = L10n.of(context).settingsSyncWebdav;
  final webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);

  // 初始化表单控制器
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);

  // 构建文本输入框组件
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  // 显示对话框
  showDialog(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          // WebDAV URL输入框
          buildTextField(
              L10n.of(context).settingsSyncWebdavUrl, webdavUrlController),
          // 用户名输入框
          buildTextField(L10n.of(context).settingsSyncWebdavUsername,
              webdavUsernameController),
          // 密码输入框
          buildTextField(L10n.of(context).settingsSyncWebdavPassword,
              webdavPasswordController),
          // 按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 测试连接按钮
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(L10n.of(context).settingsSyncWebdavTestConnection),
              ),
              // 保存按钮
              TextButton(
                onPressed: () {
                  // 更新WebDAV信息
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  // 保存到偏好设置
                  Prefs().setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  // 初始化同步客户端
                  SyncClientFactory.initializeCurrentClient();
                  // 关闭对话框
                  Navigator.pop(context);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
