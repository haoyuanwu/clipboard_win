part of 'app.dart';

/// Storage preferences share one label/control/description rhythm.
class TransferStorageSettings extends StatelessWidget {
  const TransferStorageSettings({super.key, required this.store});
  final ClipboardStore store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(context, '悬浮中转', CupertinoIcons.tray),
      _card(
        context,
        Column(
          children: [
            _preference(
              context,
              title: '拖入文件夹',
              description: '作为文件组时展开第一层，子文件夹和空文件夹保持完整。',
              control: _folderChoice(context),
            ),
            _divider(context),
            _preference(
              context,
              title: '同时保存到历史记录',
              description: '关闭时仅保留在中转站，开启后同步收录到历史记录。',
              control: Semantics(
                label: '同时保存到历史记录',
                child: SizedBox(
                  width: 38,
                  height: 24,
                  child: FittedBox(
                    child: CupertinoSwitch(
                      value: store.settings['transferHistory'] == true,
                      activeTrackColor: const Color(0xff1f5ce0),
                      onChanged: (v) => store.setting('transferHistory', v),
                    ),
                  ),
                ),
              ),
            ),
            _divider(context),
            _preference(
              context,
              title: '关闭后自动清空',
              description: '重新打开即取消倒计时，仅清理中转副本。',
              control: _timeout(context),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.info_circle,
              size: 13,
              color: secondary(context),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text('拖动文件即可唤出快捷收纳入口。', style: _descriptionStyle(context)),
            ),
          ],
        ),
      ),
      _heading(context, '记事本', CupertinoIcons.book),
      _card(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('保存位置', style: _labelStyle(context)),
              const SizedBox(height: 10),
              Tooltip(
                message: store.notebookPath,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        WindowsBridge.call('openFolder', store.notebookPath),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: control(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.folder,
                            size: 18,
                            color: accent(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              store.notebookPath,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: _descriptionStyle(context).copyWith(
                                color: ReplicaMetrics.primary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.arrow_up_right,
                            size: 12,
                            color: secondary(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: store.busy
                      ? null
                      : () async {
                          final path = await WindowsBridge.call<String>(
                            'chooseFolder',
                          );
                          if (path != null && path.isNotEmpty) {
                            await store.command({
                              'op': 'migrate',
                              'path': path,
                            });
                          }
                        },
                  icon: store.busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(CupertinoIcons.folder_badge_plus, size: 15),
                  label: Text(store.busy ? '正在保存或迁移…' : '更改保存位置…'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    foregroundColor: accent(context),
                    side: BorderSide(color: ReplicaMetrics.border(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: ReplicaMetrics.fontFamily,
                      fontFamilyFallback: ReplicaMetrics.fontFallback,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '内容保存为独立副本，永久保留。更改位置会迁移已有内容。',
                style: _descriptionStyle(context),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
    ],
  );

  TextStyle _labelStyle(BuildContext c) => TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: ReplicaMetrics.primary(c),
    fontFamily: ReplicaMetrics.fontFamily,
    fontFamilyFallback: ReplicaMetrics.fontFallback,
  );
  TextStyle _descriptionStyle(BuildContext c) => TextStyle(
    fontSize: 12,
    height: 1.55,
    color: secondary(c),
    fontFamily: ReplicaMetrics.fontFamily,
    fontFamilyFallback: ReplicaMetrics.fontFallback,
  );
  Widget _heading(BuildContext c, String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 15, color: secondary(c)),
        const SizedBox(width: 8),
        Text(text, style: _labelStyle(c).copyWith(fontSize: 14)),
      ],
    ),
  );
  Widget _card(BuildContext c, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: (isDark(c) ? const Color(0xff30333a) : Colors.white).withValues(
        alpha: .70,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: ReplicaMetrics.border(c).withValues(alpha: .09),
        width: .75,
      ),
    ),
    child: child,
  );
  Widget _divider(BuildContext c) => Divider(
    height: 1,
    thickness: .5,
    color: ReplicaMetrics.border(c).withValues(alpha: .08),
  );
  Widget _preference(
    BuildContext c, {
    required String title,
    required String description,
    required Widget control,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(child: Text(title, style: _labelStyle(c))),
              const SizedBox(width: 12),
              control,
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(description, style: _descriptionStyle(c)),
      ],
    ),
  );
  Widget _folderChoice(BuildContext c) {
    const choices = {'ask': '每次询问', 'group': '作为文件组', 'folder': '保留文件夹'};
    final value = store.settings['folderDropMode'] as String? ?? 'ask';
    return PopupMenuButton<String>(
      tooltip: '拖入文件夹',
      initialValue: value,
      onSelected: (v) => store.setting('folderDropMode', v),
      itemBuilder: (_) => choices.entries
          .map(
            (e) =>
                PopupMenuItem(value: e.key, height: 36, child: Text(e.value)),
          )
          .toList(),
      child: Container(
        width: 112,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: control(c),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: ReplicaMetrics.border(c), width: .75),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                choices[value] ?? choices['ask']!,
                style: _labelStyle(c)
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ),
            const Icon(CupertinoIcons.chevron_down, size: 10),
          ],
        ),
      ),
    );
  }

  Widget _timeout(BuildContext c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 52,
        child: Semantics(
          label: '关闭后清空时间，单位分钟，1 至 1440',
          child: TextFormField(
            key: ValueKey(
              'transfer-timeout-${store.settings['transferMinutes']}',
            ),
            initialValue: '${store.settings['transferMinutes']}',
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: _labelStyle(c).copyWith(fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 7,
              ),
              filled: true,
              fillColor: control(c),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onFieldSubmitted: (v) =>
                store.setting('transferMinutes', int.tryParse(v) ?? 10),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text('分钟', style: _descriptionStyle(c)),
      const SizedBox(width: 8),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _step(c, '增加清空时间', CupertinoIcons.chevron_up, 1),
          _step(c, '减少清空时间', CupertinoIcons.chevron_down, -1),
        ],
      ),
    ],
  );
  Widget _step(BuildContext c, String label, IconData icon, int delta) {
    final value = store.settings['transferMinutes'] as int;
    final enabled = delta > 0 ? value < 1440 : value > 1;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: enabled,
        child: InkWell(
          onTap: enabled
              ? () => store.setting('transferMinutes', value + delta)
              : null,
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 24,
            height: 16,
            child: Icon(
              icon,
              size: 10,
              color: enabled ? secondary(c) : Theme.of(c).disabledColor,
            ),
          ),
        ),
      ),
    );
  }
}
