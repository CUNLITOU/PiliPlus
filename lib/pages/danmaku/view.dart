import 'dart:convert';

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/pages/danmaku/controller.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 传入播放器控制器，监听播放进度，加载对应弹幕
class PlDanmaku extends StatefulWidget {
  final int cid;
  final PlPlayerController playerController;
  final bool isPipMode;
  final bool isFullScreen;
  final bool isFileSource;
  final Size size;

  const PlDanmaku({
    super.key,
    required this.cid,
    required this.playerController,
    this.isPipMode = false,
    required this.isFullScreen,
    required this.isFileSource,
    required this.size,
  });

  @override
  State<PlDanmaku> createState() => _PlDanmakuState();

  bool get notFullscreen => !isFullScreen || isPipMode;
}

class _PlDanmakuState extends State<PlDanmaku> {
  PlPlayerController get playerController => widget.playerController;

  late final PlDanmakuController _plDanmakuController;
  DanmakuController<DanmakuExtra>? _controller;
  int latestAddedPosition = -1;

  @override
  void initState() {
    super.initState();
    _plDanmakuController = PlDanmakuController(
      widget.cid,
      playerController,
      widget.isFileSource,
    );
    if (playerController.enableShowDanmaku.value) {
      if (widget.isFileSource) {
        _plDanmakuController.initFileDmIfNeeded();
      } else {
        _plDanmakuController.queryDanmaku(
          DmUtils.calcSegment(playerController.positionInMilliseconds),
        );
      }
    }
    playerController
      ..addStatusLister(playerListener)
      ..addPositionListener(videoPositionListen);
  }

  @override
  void didUpdateWidget(PlDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notFullscreen != widget.notFullscreen &&
        !DanmakuOptions.sameFontScale) {
      _controller?.updateOption(
        DanmakuOptions.get(
          notFullscreen: widget.notFullscreen,
          speed: playerController.playbackSpeed,
        ),
      );
    }
  }

  // 播放器状态监听
  void playerListener(PlayerStatus status) {
    if (_controller case final controller?) {
      if (status.isPlaying) {
        controller.resume();
      } else {
        controller.pause();
      }
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void videoPositionListen(Duration position) {
    if (_controller == null || !playerController.enableShowDanmaku.value) {
      return;
    }

    if (!playerController.showDanmaku && !widget.isPipMode) {
      return;
    }

    if (!playerController.playerStatus.isPlaying) {
      return;
    }

    int currentPosition = position.inMilliseconds;
    currentPosition -= currentPosition % 100; //取整百的毫秒数
    if (currentPosition == latestAddedPosition) {
      return;
    }
    latestAddedPosition = currentPosition;

    List<DanmakuElem>? currentDanmakuList = _plDanmakuController
        .getCurrentDanmaku(currentPosition);
    if (currentDanmakuList != null) {
      final blockColorful = DanmakuOptions.blockColorful;
      final danmakuWeight = DanmakuOptions.danmakuWeight;
      final option = _controller!.option;
      for (DanmakuElem e in currentDanmakuList) {
        if (e.weight < danmakuWeight) continue;
        // 预判该弹幕是否会被隐藏，避免无谓的对象构造与后续绘制开销
        final type = DmUtils.getPosition(e.mode);
        if (type == DanmakuItemType.scroll) {
          if (option.hideScroll) continue;
        } else if (type == DanmakuItemType.top) {
          if (option.hideTop) continue;
        } else if (type == DanmakuItemType.bottom) {
          if (option.hideBottom) continue;
        } else if (option.hideSpecial) {
          continue;
        }
        if (e.mode == 7) {
          try {
            _pendingDanmaku.add(
              SpecialDanmakuContentItem.fromList(
                DmUtils.decimalToColor(e.color),
                e.fontsize.toDouble(),
                jsonDecode(e.content.replaceAll('\n', '\\n')),
                extra: VideoDanmaku(
                  id: e.id.toInt(),
                  mid: e.midHash,
                  like: e.likeCount.toInt(),
                ),
              ),
            );
          } catch (_) {}
        } else {
          final content = e.content.trim();
          if (content.isEmpty) continue;
          _pendingDanmaku.add(
            DanmakuContentItem(
              content,
              color: blockColorful
                  ? Colors.white
                  : DmUtils.decimalToColor(e.color),
              type: type,
              isColorful:
                  playerController.showVipDanmaku &&
                  e.colorful == DmColorfulType.VipGradualColor,
              count: e.count > 1 ? e.count : null,
              selfSend: e.isSelf,
              extra: VideoDanmaku(
                id: e.id.toInt(),
                mid: e.midHash,
                like: e.likeCount.toInt(),
              ),
            ),
          );
        }
      }
    }
    _flushPendingDanmaku();
  }

  /// 单次最多添加入渲染队列的弹幕数量，避免拖进度/切P时大量弹幕
  /// 集中在同一帧处理导致界面卡死
  static const int _maxAddPerTick = 20;

  /// 待添加的弹幕，超出单次上限的部分顺延到后续帧
  final List<DanmakuContentItem<DanmakuExtra>> _pendingDanmaku = [];
  static const int _maxPending = 400;

  void _flushPendingDanmaku() {
    final controller = _controller;
    if (controller == null || _pendingDanmaku.isEmpty) {
      return;
    }
    final end = _pendingDanmaku.length < _maxAddPerTick
        ? _pendingDanmaku.length
        : _maxAddPerTick;
    for (var i = 0; i < end; i++) {
      controller.addDanmaku(_pendingDanmaku[i]);
    }
    if (end == _pendingDanmaku.length) {
      _pendingDanmaku.clear();
    } else {
      _pendingDanmaku.removeRange(0, end);
      // 极端情况下限制积压，防止内存与延迟持续增长
      if (_pendingDanmaku.length > _maxPending) {
        _pendingDanmaku.removeRange(0, _pendingDanmaku.length - _maxPending);
      }
    }
  }

  @override
  void dispose() {
    _pendingDanmaku.clear();
    playerController
      ..removePositionListener(videoPositionListen)
      ..removeStatusLister(playerListener);
    _plDanmakuController.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final option = DanmakuOptions.get(
      notFullscreen: widget.notFullscreen,
      speed: playerController.playbackSpeed,
    );
    return Obx(
      () => AnimatedOpacity(
        opacity: playerController.enableShowDanmaku.value
            ? playerController.danmakuOpacity.value
            : 0,
        duration: const Duration(milliseconds: 100),
        child: DanmakuScreen<DanmakuExtra>(
          createdController: (e) {
            playerController.danmakuController = _controller = e;
          },
          option: option,
          size: widget.size,
        ),
      ),
    );
  }
}
