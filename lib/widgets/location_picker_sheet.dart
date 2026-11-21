import 'package:flutter/material.dart';
import 'package:shi_wu_ji/constants/app_colors.dart';
import 'package:shi_wu_ji/providers/storage_providers.dart';
import 'package:shi_wu_ji/widgets/emoji_text.dart';

/// 收纳位置选择底部弹窗（从 [storageLocationTreeProvider] 的格子节点中单选）。
///
/// 由新增/编辑物品页与智能录入页共用；
/// 数据获取（Provider 监听）由调用方完成，本组件只负责展示与回调。
class LocationPickerSheet extends StatelessWidget {
  final List<StorageLocationNode> nodes;
  final bool isLoading;
  final StorageLocationNode? selectedNode;
  final ValueChanged<StorageLocationNode> onPick;
  final VoidCallback onClear;

  const LocationPickerSheet({
    super.key,
    required this.nodes,
    required this.isLoading,
    required this.selectedNode,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = screenHeight * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部把手
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择收纳位置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: '清除选择',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // 列表
          Flexible(
            child: isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: AppColors.accentGold,
                      ),
                    ),
                  )
                : nodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        '暂无可用格子区域\n请先在收纳页面添加柜体和格子',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: nodes.length,
                    itemBuilder: (ctx, i) {
                      final node = nodes[i];
                      final isSelected =
                          selectedNode?.id == node.id &&
                          selectedNode?.isSlot == node.isSlot;
                      return LocationTile(
                        node: node,
                        isSelected: isSelected,
                        onTap: () => onPick(node),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 位置选择弹窗的单行条目（房间 / 柜体 / 格子路径展示）。
class LocationTile extends StatelessWidget {
  final StorageLocationNode node;
  final bool isSelected;
  final VoidCallback onTap;

  const LocationTile({
    super.key,
    required this.node,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF8E7) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accentGold : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // 层级图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: node.isSlot
                    ? const Color(0xFFE8F0FE)
                    : const Color(0xFFFFF3CC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: EmojiText(emoji: node.emoji, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            // 路径信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node.pathLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 选中标记
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.accentGold,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
