part of 'admin_bloc.dart';

abstract class AdminState extends Equatable {
  const AdminState();

  @override
  List<Object?> get props => [];
}

class AdminInitial extends AdminState {}

class AdminLoading extends AdminState {}

class AdminError extends AdminState {
  final String message;

  const AdminError(this.message);

  @override
  List<Object> get props => [message];
}

class DashboardStatsLoaded extends AdminState {
  final AdminDashboardStats stats;

  const DashboardStatsLoaded(this.stats);

  @override
  List<Object> get props => [stats];
}

class UsersLoaded extends AdminState {
  final List<AdminUser> users;

  const UsersLoaded(this.users);

  @override
  List<Object> get props => [users];
}

class UsersPageLoaded extends AdminState {
  final List<AdminUser> users;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  const UsersPageLoaded({
    required this.users,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  @override
  List<Object> get props => [users, page, size, totalElements, totalPages];
}

class RolesLoaded extends AdminState {
  final List<AdminRole> roles;

  const RolesLoaded(this.roles);

  @override
  List<Object> get props => [roles];
}

class ModelConfigsLoaded extends AdminState {
  final List<AdminModelConfig> configs;

  const ModelConfigsLoaded(this.configs);

  @override
  List<Object> get props => [configs];
}

class SystemConfigsLoaded extends AdminState {
  final List<AdminSystemConfig> configs;

  const SystemConfigsLoaded(this.configs);

  @override
  List<Object> get props => [configs];
}