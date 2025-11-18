import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../services/api_service/repositories/impl/admin_repository_impl.dart';
import '../../models/admin/admin_models.dart';

part 'admin_event.dart';
part 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final AdminRepositoryImpl adminRepository;

  AdminBloc(this.adminRepository) : super(AdminInitial()) {
    on<LoadDashboardStats>(_onLoadDashboardStats);
    on<LoadUsers>(_onLoadUsers);
    on<LoadRoles>(_onLoadRoles);
    on<LoadModelConfigs>(_onLoadModelConfigs);
    on<LoadSystemConfigs>(_onLoadSystemConfigs);
    on<UpdateUserStatus>(_onUpdateUserStatus);
    on<CreateRole>(_onCreateRole);
    on<UpdateRole>(_onUpdateRole);
    on<UpdateModelConfig>(_onUpdateModelConfig);
    on<UpdateSystemConfig>(_onUpdateSystemConfig);
    on<AddCreditsToUser>(_onAddCreditsToUser);
    on<DeductCreditsFromUser>(_onDeductCreditsFromUser);
    on<UpdateUserInfo>(_onUpdateUserInfo);
    on<AssignRoleToUser>(_onAssignRoleToUser);
    on<ResetUserPassword>(_onResetUserPassword);
    on<BumpUserTokenVersion>(_onBumpUserTokenVersion);
  }

  Future<void> _onLoadDashboardStats(
    LoadDashboardStats event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      final stats = await adminRepository.getDashboardStats();
      emit(DashboardStatsLoaded(stats));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onLoadUsers(
    LoadUsers event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      // 使用新的分页接口
      final paged = await adminRepository.getUsersPaged(
        page: event.page,
        size: event.size,
        keyword: event.search,
        status: event.status,
        minCredits: event.minCredits,
        createdStart: event.createdStart,
        createdEnd: event.createdEnd,
        lastLoginStart: event.lastLoginStart,
        lastLoginEnd: event.lastLoginEnd,
        sortBy: event.sortBy,
        sortDir: event.sortDir,
      );
      emit(UsersPageLoaded(
        users: paged.content,
        page: paged.page,
        size: paged.size,
        totalElements: paged.totalElements,
        totalPages: paged.totalPages,
      ));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onLoadRoles(
    LoadRoles event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      final roles = await adminRepository.getRoles();
      emit(RolesLoaded(roles));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onLoadModelConfigs(
    LoadModelConfigs event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      final configs = await adminRepository.getModelConfigs();
      emit(ModelConfigsLoaded(configs));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onLoadSystemConfigs(
    LoadSystemConfigs event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      final configs = await adminRepository.getSystemConfigs();
      emit(SystemConfigsLoaded(configs));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onUpdateUserStatus(
    UpdateUserStatus event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.updateUserStatus(event.userId, event.status);
      // 重新加载用户列表
      add(LoadUsers());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onCreateRole(
    CreateRole event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.createRole(event.role);
      // 重新加载角色列表
      add(LoadRoles());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onUpdateRole(
    UpdateRole event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.updateRole(event.roleId, event.role);
      // 重新加载角色列表
      add(LoadRoles());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onUpdateModelConfig(
    UpdateModelConfig event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.updateModelConfig(event.configId, event.config);
      // 重新加载模型配置列表
      add(LoadModelConfigs());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onUpdateSystemConfig(
    UpdateSystemConfig event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.updateSystemConfig(event.configKey, event.value);
      // 重新加载系统配置列表
      add(LoadSystemConfigs());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onAddCreditsToUser(
    AddCreditsToUser event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.addCreditsToUser(event.userId, event.amount, event.reason);
      // 重新加载用户列表
      add(LoadUsers());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onDeductCreditsFromUser(
    DeductCreditsFromUser event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.deductCreditsFromUser(event.userId, event.amount, event.reason);
      // 重新加载用户列表
      add(LoadUsers());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onUpdateUserInfo(
    UpdateUserInfo event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.updateUserInfo(
        event.userId, 
        email: event.email,
        displayName: event.displayName,
        accountStatus: event.accountStatus,
      );
      // 重新加载用户列表
      add(LoadUsers());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onAssignRoleToUser(
    AssignRoleToUser event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.assignRoleToUser(event.userId, event.roleId);
      // 重新加载用户列表
      add(LoadUsers());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onResetUserPassword(
    ResetUserPassword event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.resetUserPassword(event.userId, newPassword: event.newPassword);
      // 重置成功后刷新列表
      add(const LoadUsers());
      // 可以考虑添加成功状态，但这里直接刷新列表更简洁
    } catch (e) {
      String errorMessage = '重置密码失败';
      if (e.toString().contains('用户不存在')) {
        errorMessage = '用户不存在，无法重置密码';
      } else if (e.toString().contains('权限')) {
        errorMessage = '没有权限执行此操作';
      } else if (e.toString().contains('网络')) {
        errorMessage = '网络连接失败，请稍后重试';
      }
      emit(AdminError('$errorMessage: ${e.toString()}'));
    }
  }

  Future<void> _onBumpUserTokenVersion(
    BumpUserTokenVersion event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await adminRepository.bumpUserTokenVersion(event.userId);
      add(const LoadUsers());
    } catch (e) {
      emit(AdminError('强制下线失败: ${e.toString()}'));
    }
  }
}