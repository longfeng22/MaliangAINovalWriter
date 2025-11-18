part of 'sidebar_bloc.dart';

abstract class SidebarState extends Equatable {
  const SidebarState();

  @override
  List<Object?> get props => [];
}

class SidebarInitial extends SidebarState {}

class SidebarLoading extends SidebarState {}

class SidebarLoaded extends SidebarState {
  final Novel novelStructure; // 包含完整结构和场景摘要的小说对象

  const SidebarLoaded({required this.novelStructure});

  @override
  List<Object?> get props => [novelStructure];
}

extension SidebarLoadedCopy on SidebarLoaded {
  SidebarLoaded copyWith({Novel? novelStructure}) {
    return SidebarLoaded(novelStructure: novelStructure ?? this.novelStructure);
  }
}

class SidebarError extends SidebarState {
  final String message;

  const SidebarError({required this.message});

  @override
  List<Object?> get props => [message];
} 