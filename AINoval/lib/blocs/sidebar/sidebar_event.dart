part of 'sidebar_bloc.dart';



abstract class SidebarEvent extends Equatable {
  const SidebarEvent();

  @override
  List<Object> get props => [];
}

// 加载小说结构和摘要事件
class LoadNovelStructure extends SidebarEvent {
  final String novelId;

  const LoadNovelStructure(this.novelId);

  @override
  List<Object> get props => [novelId];
}

// 增量应用结构更新（本地合并）
class ApplyIncrementalStructureUpdate extends SidebarEvent {
  final String novelId;
  final String? actId;
  final String? chapterId;
  final String? chapterTitle;
  final String? sceneId;

  const ApplyIncrementalStructureUpdate({
    required this.novelId,
    this.actId,
    this.chapterId,
    this.chapterTitle,
    this.sceneId,
  });

  @override
  List<Object> get props => [
    novelId,
    actId ?? '',
    chapterId ?? '',
    chapterTitle ?? '',
    sceneId ?? '',
  ];
}