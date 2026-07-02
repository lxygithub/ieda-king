import 'package:flutter/material.dart';

import '../models/shared_file.dart';

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  bool get _isZh => locale.languageCode == 'zh';

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // ===== General =====
  String get appTitle => _isZh ? '点子王' : 'Idea King';
  String get timeline => _isZh ? '时间线' : 'Timeline';
  String get search => _isZh ? '搜索' : 'Search';
  String get close => _isZh ? '关闭' : 'Close';
  String get cancel => _isZh ? '取消' : 'Cancel';
  String get delete => _isZh ? '删除' : 'Delete';
  String get save => _isZh ? '保存' : 'Save';
  String get done => _isZh ? '完成' : 'Done';
  String get add => _isZh ? '添加' : 'Add';
  String get edit => _isZh ? '编辑' : 'Edit';
  String get manage => _isZh ? '管理' : 'Manage';
  String get copy => _isZh ? '复制' : 'Copy';
  String get copied => _isZh ? '已复制' : 'Copied';
  String get share => _isZh ? '分享' : 'Share';
  String get noPreview => _isZh ? '无预览' : 'No preview';

  // ===== File types =====
  String get typeImage => _isZh ? '图片' : 'Image';
  String get typeText => _isZh ? '文本' : 'Text';
  String get typeMarkdown => 'Markdown';
  String get typeDocument => _isZh ? '文档' : 'Document';
  String get typeUrl => _isZh ? '链接' : 'Link';
  String get typeVideo => _isZh ? '视频' : 'Video';
  String get typeAudio => _isZh ? '音频' : 'Audio';
  String get typeApk => _isZh ? 'APK' : 'APK';
  String get typeOther => _isZh ? '其他' : 'Other';
  String get allTypes => _isZh ? '全部' : 'All';

  String translateType(SharedFileType type) {
    switch (type) {
      case SharedFileType.image: return typeImage;
      case SharedFileType.text: return typeText;
      case SharedFileType.markdown: return typeMarkdown;
      case SharedFileType.document: return typeDocument;
      case SharedFileType.url: return typeUrl;
      case SharedFileType.video: return typeVideo;
      case SharedFileType.audio: return typeAudio;
      case SharedFileType.apk: return typeApk;
      case SharedFileType.other: return typeOther;
    }
  }

  String fileTypeLabel(String type) => _isZh ? type : type; // shared file type, usually same

  // ===== Timeline =====
  String get today => _isZh ? '今天' : 'Today';
  String get yesterday => _isZh ? '昨天' : 'Yesterday';
  String get dayBefore => _isZh ? '前天' : 'Day before';
  String daysAgo(int n) => _isZh ? '$n天前' : '$n days ago';
  String get noFilesYet => _isZh ? '还没有收到任何分享' : 'No files yet';
  String get shareHint => _isZh ? '从其他应用分享文件、图片或文字到此应用' : 'Share files, images or text from other apps';
  String get listView => _isZh ? '列表视图' : 'List view';
  String get gridView => _isZh ? '网格视图' : 'Grid view';
  String items(int n) => _isZh ? '$n 项' : '$n items';
  String get noTag => _isZh ? '无标签' : 'No tags';
  String get tagLabel => _isZh ? '标签' : 'Tags';
  String get descriptionLabel => _isZh ? '描述' : 'Description';
  String get addDescription => _isZh ? '添加描述...' : 'Add description...';
  String get addTag => _isZh ? '添加标签' : 'Add tag';
  String get tagHint => _isZh ? '输入标签名，回车确认' : 'Enter tag name, press enter';
  String get openWith => _isZh ? '选择打开方式' : 'Open with';
  String get systemApp => _isZh ? '系统应用' : 'System app';
  String get chooseApp => _isZh ? '选择其他应用打开' : 'Open with other app';
  String get copyPath => _isZh ? '复制路径' : 'Copy path';
  String get copyText => _isZh ? '复制文本' : 'Copy text';
  String get noText => _isZh ? '无文本内容可复制' : 'No text to copy';
  String get noPath => _isZh ? '无文件路径' : 'No file path';
  String get noShareContent => _isZh ? '无可分享的内容' : 'Nothing to share';
  String get openFailed => _isZh ? '打开失败' : 'Open failed';
  String get emptyPath => _isZh ? '文件路径为空' : 'File path is empty';

  // ===== Detail =====
  String get detailInfo => _isZh ? '详细信息' : 'Details';
  String get fileName => _isZh ? '文件名' : 'File name';
  String get fileType => _isZh ? '类型' : 'Type';
  String get fileSize => _isZh ? '大小' : 'Size';
  String get receiveTime => _isZh ? '接收时间' : 'Received at';
  String get localPath => _isZh ? '本地路径' : 'Local path';
  String get source => _isZh ? '来源' : 'Source';
  String get deleteRecord => _isZh ? '删除记录' : 'Delete record';
  String deleteConfirm(String name) => _isZh ? '从时间线移除 "$name"？(本地文件保留)' : 'Remove "$name" from timeline? (Local file kept)';
  String get searchPlaceholder => _isZh ? '搜索文件名、标签、描述...' : 'Search name, tags, description...';
  String searchResult(int n) => _isZh ? '$n 个结果' : '$n results';
  String searchLabel(String q) => _isZh ? '搜索: "$q"' : 'Search: "$q"';

  // ===== Filter =====
  String get typeFilter => _isZh ? '类型筛选' : 'Type filter';
  String get clear => _isZh ? '清除' : 'Clear';

  // ===== Selection =====
  String selected(int n) => _isZh ? '已选 $n 项' : '$n selected';
  String get batchDelete => _isZh ? '批量删除' : 'Batch delete';
  String batchDeleteConfirm(int n) => _isZh ? '从时间线移除选中的 $n 条记录？(本地文件保留)' : 'Remove $n records from timeline? (Local files kept)';
  String get batchAddTag => _isZh ? '添加标签' : 'Add tags';
  String batchAddTagConfirm(int n, int tagCount) =>
      _isZh ? '为选中的 $n 个文件添加 $tagCount 个标签' : 'Add $tagCount tags to $n selected files';
  String get batchAddTagHint => _isZh ? '输入标签名，回车确认。将追加到已有标签' : 'Enter tag name, press enter. Appended to existing tags';
  String get batchAddTagSuccess => _isZh ? '标签已添加' : 'Tags added';

  // ===== Day delete =====
  String get deleteDayTitle => _isZh ? '删除当天记录' : 'Delete day records';
  String deleteDayConfirm(String date, int n) => _isZh ? '从时间线移除 $date 的 $n 条记录？(本地文件保留)' : 'Remove $n records from $date? (Local files kept)';

  // ===== Draggable FAB =====
  String get addContent => _isZh ? '添加内容' : 'Add content';
  String get pickFile => _isZh ? '从文件管理器选择' : 'Pick from files';
  String get pickFileSub => _isZh ? '选择图片、文档等文件' : 'Select images, documents, etc.';
  String get inputText => _isZh ? '输入文本' : 'Input text';
  String get inputTextSub => _isZh ? '手动输入或粘贴文字' : 'Type or paste text';
  String get importClipboard => _isZh ? '从剪贴板导入' : 'Import from clipboard';
  String get importClipboardSub => _isZh ? '粘贴剪贴板最新内容' : 'Paste latest clipboard content';
  String get clipboardEmpty => _isZh ? '剪贴板为空' : 'Clipboard is empty';
  String get imported => _isZh ? '已从剪贴板导入' : 'Imported from clipboard';
  String get textInputTitle => _isZh ? '输入文本' : 'Input text';
  String get textHint => _isZh ? '在此输入或粘贴文字...' : 'Type or paste text here...';
  String charCount(int n) => _isZh ? '$n 字' : '$n chars';

  // ===== Date format =====
  String formatDate(DateTime date) {
    if (_isZh) {
      return '${date.month}月${date.day}日';
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  // ===== Weekdays =====
  List<String> get weekdays => _isZh
      ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // ===== Expand/Collapse =====
  String get expandAll => _isZh ? '展开全部' : 'Expand all';
  String get collapse => _isZh ? '收起' : 'Collapse';
  String expandN(int n) => _isZh ? '展开$n项' : 'Expand $n';
  String get collapseN => _isZh ? '收起' : 'Collapse';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      Future.value(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
