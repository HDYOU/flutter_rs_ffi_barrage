import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// 崩溃记录数据结构
// ---------------------------------------------------------------------------

/// 崩溃记录
class CrashInfo {
  final dynamic error;
  final StackTrace? stackTrace;
  final DateTime time;

  CrashInfo(this.error, this.stackTrace, this.time);
}

/// 全局崩溃历史记录
final List<CrashInfo> crashHistory = [];

// ---------------------------------------------------------------------------
// 崩溃报告页面
// ---------------------------------------------------------------------------

/// 崩溃/异常报告页面
///
/// 当应用发生未捕获异常时，自动跳转到该页面展示错误详情，
/// 方便开发者定位问题。包含：
/// - 异常类型和消息
/// - 完整堆栈跟踪
/// - 异常发生时间
/// - 复制到剪贴板功能
/// - 历史崩溃记录查看
class CrashReportPage extends StatefulWidget {
  final dynamic error;
  final StackTrace? stackTrace;

  const CrashReportPage({super.key, required this.error, this.stackTrace});

  @override
  State<CrashReportPage> createState() => _CrashReportPageState();
}

class _CrashReportPageState extends State<CrashReportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    final buffer = StringBuffer();
    buffer.writeln('异常类型: ${widget.error.runtimeType}');
    buffer.writeln('发生时间: ${_formatDateTime(DateTime.now())}');
    buffer.writeln();
    buffer.writeln('异常信息:');
    buffer.writeln(widget.error.toString());
    if (widget.stackTrace != null) {
      buffer.writeln();
      buffer.writeln('堆栈跟踪:');
      buffer.writeln(widget.stackTrace.toString());
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE74C3C),
        foregroundColor: Colors.white,
        title: const Row(
          children: [Icon(Icons.bug_report), SizedBox(width: 8), Text('应用异常')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制错误信息',
            onPressed: _copyToClipboard,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: '当前异常'), Tab(text: '历史记录')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCurrentError(), _buildHistoryList()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回应用'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      crashHistory.clear();
                    });
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('清空并继续'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE74C3C),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentError() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 错误类型标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.error.runtimeType.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 错误消息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D44),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE74C3C).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              widget.error.toString(),
              style: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 发生时间
          _buildInfoRow(
            icon: Icons.access_time,
            label: '发生时间',
            value: _formatDateTime(DateTime.now()),
          ),
          const SizedBox(height: 16),

          // 堆栈信息标题
          const Row(
            children: [
              Icon(Icons.list_alt, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                '堆栈跟踪',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 堆栈信息
          if (widget.stackTrace != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                widget.stackTrace.toString(),
                style: const TextStyle(
                  color: Color(0xFFA0A0C0),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            )
          else
            const Text('无堆栈信息', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    if (crashHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            SizedBox(height: 12),
            Text(
              '暂无历史崩溃记录',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: crashHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final crash = crashHistory[index];
        final isLatest = index == crashHistory.length - 1;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D44),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isLatest
                      ? const Color(0xFFE74C3C).withValues(alpha: 0.5)
                      : Colors.white10,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  isLatest ? const Color(0xFFE74C3C) : Colors.orange,
              child: Icon(
                isLatest ? Icons.bug_report : Icons.history,
                color: Colors.white,
                size: 18,
              ),
            ),
            title: Text(
              crash.error.runtimeType.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _formatDateTime(crash.time),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _showCrashDetail(context, crash),
          ),
        );
      },
    );
  }

  void _showCrashDetail(BuildContext context, CrashInfo crash) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(crash.error.runtimeType.toString()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crash.error.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  if (crash.stackTrace != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '堆栈跟踪:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      crash.stackTrace.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// 工具函数
// ---------------------------------------------------------------------------

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min:$s';
}
