import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class VideoReplyPanel extends StatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.heroTag,
    required this.isNested,
  });

  final int replyLevel;
  final String heroTag;
  final bool isNested;

  @override
  State<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends State<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        FabMixin {
  late VideoReplyController _videoReplyController;

  String get heroTag => widget.heroTag;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videoReplyController = Get.find<VideoReplyController>(tag: heroTag);
    if (_videoReplyController.loadingState.value is Loading) {
      _videoReplyController.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    bottom = MediaQuery.viewPaddingOf(context).bottom;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final child = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        switch (notification.direction) {
          case .forward:
            showFab();
          case .reverse:
            hideFab();
          case _:
        }
        return false;
      },
      child: refreshIndicator(
        onRefresh: _videoReplyController.onRefresh,
        isClampingScrollPhysics: widget.isNested,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomScrollView(
              controller: widget.isNested
                  ? null
                  : _videoReplyController.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              key: const PageStorageKey(_VideoReplyPanelState),
              slivers: [
                SliverFloatingHeaderWidget(
                  backgroundColor: theme.colorScheme.surface,
                  child: Padding(
                    padding: const .fromLTRB(12, 2.5, 6, 2.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Obx(
                          () => Text(
                            _videoReplyController.sortType.value.title,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Row(
                          children: [
                            // 刷新按钮
                            TextButton.icon(
                              style: StyleString.buttonStyle,
                              onPressed: _videoReplyController.onRefresh,
                              icon: Icon(
                                Icons.refresh,
                                size: 16,
                                color: theme.colorScheme.secondary,
                              ),
                              label: Text(
                                '刷新',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ),
                            // 只看UP主按钮
                            Obx(
                              () => TextButton.icon(
                                style: StyleString.buttonStyle,
                                onPressed: _videoReplyController.toggleShowOnlyUp,
                                icon: Icon(
                                  _videoReplyController.showOnlyUp.value
                                      ? Icons.person
                                      : Icons.person_outline,
                                  size: 16,
                                  color: _videoReplyController.showOnlyUp.value
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.secondary,
                                ),
                                label: Text(
                                  '只看UP主',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _videoReplyController.showOnlyUp.value
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: StyleString.buttonStyle,
                              onPressed: _videoReplyController.queryBySort,
                              icon: Icon(
                                Icons.sort,
                                size: 16,
                                color: theme.colorScheme.secondary,
                              ),
                              label: Obx(
                                () => Text(
                                  _videoReplyController.sortType.value.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Obx(
                  () => _buildBody(
                    theme,
                    _videoReplyController.loadingState.value,
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: fabAnimation,
                child: Padding(
                  padding: .only(
                    right: kFloatingActionButtonMargin,
                    bottom: kFloatingActionButtonMargin + bottom,
                  ),
                  child: FloatingActionButton(
                    heroTag: null,
                    onPressed: () {
                      feedBack();
                      _videoReplyController.onReply(
                        null,
                        oid: _videoReplyController.aid,
                        replyType: _videoReplyController.videoType.replyType,
                      );
                    },
                    tooltip: '发表评论',
                    child: const Icon(Icons.reply),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.isNested) {
      return ExtendedVisibilityDetector(
        uniqueKey: const Key('reply-list'),
        child: child,
      );
    }
    return child;
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => SliverList.builder(
        itemBuilder: (context, index) => const VideoReplySkeleton(),
        itemCount: 5,
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? Obx(() {
                final showOnlyUp = _videoReplyController.showOnlyUp.value;
                final upMid = _videoReplyController.upMid;
                // 根据只看UP主状态过滤评论
                final filteredResponse = showOnlyUp && upMid != null
                    ? response.where((item) => 
                        // 显示UP主自己的评论
                        item.mid == upMid ||
                        // 显示有UP主回复的评论
                        item.replies.any((reply) => reply.mid == upMid)
                      ).toList()
                    : response;
                return SliverList.builder(
                  itemBuilder: (context, index) {
                    if (index == filteredResponse.length) {
                      // 如果开启了只看UP主，不加载更多（因为服务端不支持筛选）
                      if (showOnlyUp) {
                        return Container(
                          height: 125,
                          alignment: Alignment.center,
                          margin: EdgeInsets.only(bottom: bottom),
                          child: Text(
                            '没有更多了',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        );
                      }
                      _videoReplyController.onLoadMore();
                      return Container(
                        height: 125,
                        alignment: Alignment.center,
                        margin: EdgeInsets.only(bottom: bottom),
                        child: Text(
                          _videoReplyController.isEnd ? '没有更多了' : '加载中...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      );
                    } else {
                      // 找到原始列表中的索引用于删除操作
                      final originalIndex = showOnlyUp
                          ? response.indexOf(filteredResponse[index])
                          : index;
                      return ReplyItemGrpc(
                        replyItem: filteredResponse[index],
                        replyLevel: widget.replyLevel,
                        replyReply: replyReply,
                        onReply: _videoReplyController.onReply,
                        onDelete: (item, subIndex) =>
                            _videoReplyController.onRemove(originalIndex, item, subIndex),
                        upMid: _videoReplyController.upMid,
                        getTag: () => heroTag,
                        onCheckReply: (item) => _videoReplyController
                            .onCheckReply(item, isManual: true),
                        onToggleTop: (item) => _videoReplyController.onToggleTop(
                          item,
                          originalIndex,
                          _videoReplyController.aid,
                          _videoReplyController.videoType.replyType,
                        ),
                      );
                    }
                  },
                  itemCount: filteredResponse.length + 1,
                );
              })
            : HttpError(
                errMsg: '还没有评论',
                onReload: _videoReplyController.onReload,
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _videoReplyController.onReload,
      ),
    };
  }

  // 展示二级回复
  void replyReply(ReplyInfo replyItem, int? id) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      showBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(),
        builder: (context) => VideoReplyReplyPanel(
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem.replyControl.isNote ? null : replyItem,
          replyType: _videoReplyController.videoType.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
        ),
      );
    });
  }
}
