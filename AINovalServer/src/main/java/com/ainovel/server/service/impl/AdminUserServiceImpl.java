package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Service;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;

import com.ainovel.server.controller.AdminUserController.UserStatistics;
import com.ainovel.server.controller.AdminUserController.UserUpdateRequest;
import com.ainovel.server.domain.model.User;
import com.ainovel.server.domain.model.User.AccountStatus;
import com.ainovel.server.repository.UserRepository;
import com.ainovel.server.service.AdminUserService;
import com.ainovel.server.common.response.PagedResponse;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 管理员用户管理服务实现
 */
@Service
public class AdminUserServiceImpl implements AdminUserService {
    
    private final UserRepository userRepository;
    private final ReactiveMongoTemplate mongoTemplate;
    private final PasswordEncoder passwordEncoder;
    
    @Autowired
    public AdminUserServiceImpl(UserRepository userRepository, ReactiveMongoTemplate mongoTemplate, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.mongoTemplate = mongoTemplate;
        this.passwordEncoder = passwordEncoder;
    }
    
    @Override
    public Flux<User> findAllUsers(Pageable pageable) {
        return userRepository.findAll()
                .skip(pageable.getOffset())
                .take(pageable.getPageSize());
    }
    
    @Override
    public Flux<User> searchUsers(String search, Pageable pageable) {
        // 优先尝试按 ID 精确查询（如果输入看起来像 MongoDB ObjectId）
        if (search != null && search.length() == 24 && search.matches("[0-9a-fA-F]+")) {
            // 可能是 MongoDB ObjectId，先尝试精确查询
            return userRepository.findById(search)
                    .flux()
                    .switchIfEmpty(
                        // ID 查询失败，继续按用户名/邮箱模糊查询
                        userRepository.findByUsernameContainingIgnoreCaseOrEmailContainingIgnoreCase(search, search)
                                .skip(pageable.getOffset())
                                .take(pageable.getPageSize())
                    );
        }
        
        // 普通模糊查询（用户名/邮箱）
        return userRepository.findByUsernameContainingIgnoreCaseOrEmailContainingIgnoreCase(search, search)
                .skip(pageable.getOffset())
                .take(pageable.getPageSize());
    }
    
    @Override
    public Mono<User> findUserById(String id) {
        return userRepository.findById(id);
    }
    
    @Override
    @Transactional
    public Mono<User> updateUser(String id, UserUpdateRequest request) {
        return userRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + id)))
                .flatMap(user -> {
                    if (request.getEmail() != null) {
                        user.setEmail(request.getEmail());
                    }
                    if (request.getDisplayName() != null) {
                        user.setDisplayName(request.getDisplayName());
                    }
                    if (request.getAccountStatus() != null) {
                        user.setAccountStatus(request.getAccountStatus());
                    }
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }
    
    @Override
    @Transactional
    public Mono<User> updateUserStatus(String id, AccountStatus status) {
        return userRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + id)))
                .flatMap(user -> {
                    user.setAccountStatus(status);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }
    
    @Override
    @Transactional
    public Mono<User> assignRoleToUser(String userId, String roleId) {
        return userRepository.findById(userId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + userId)))
                .flatMap(user -> {
                    user.addRole(roleId);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }
    
    @Override
    @Transactional
    public Mono<User> removeRoleFromUser(String userId, String roleId) {
        return userRepository.findById(userId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + userId)))
                .flatMap(user -> {
                    user.removeRole(roleId);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }
    
    @Override
    public Mono<UserStatistics> getUserStatistics() {
        return Mono.zip(
                userRepository.count(),
                userRepository.countByAccountStatus(AccountStatus.ACTIVE),
                userRepository.countByAccountStatus(AccountStatus.SUSPENDED),
                userRepository.countByCreatedAtAfter(LocalDateTime.now().minusDays(1)),
                userRepository.countByCreatedAtAfter(LocalDateTime.now().minusWeeks(1)),
                userRepository.countByCreatedAtAfter(LocalDateTime.now().minusMonths(1))
        ).map(tuple -> {
            UserStatistics stats = new UserStatistics();
            stats.setTotalUsers(tuple.getT1());
            stats.setActiveUsers(tuple.getT2());
            stats.setSuspendedUsers(tuple.getT3());
            stats.setNewUsersToday(tuple.getT4());
            stats.setNewUsersThisWeek(tuple.getT5());
            stats.setNewUsersThisMonth(tuple.getT6());
            return stats;
        });
    }
    
    @Override
    @Transactional
    public Mono<Long> batchUpdateUserStatus(List<String> userIds, AccountStatus status) {
        return Flux.fromIterable(userIds)
                .flatMap(userId -> updateUserStatus(userId, status))
                .count();
    }
    
    @Override
    @Transactional
    public Mono<Void> deleteUser(String id) {
        return userRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + id)))
                .flatMap(user -> {
                    // 软删除：设置为禁用状态
                    user.setAccountStatus(AccountStatus.DISABLED);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                })
                .then();
    }

    @Override
    public Mono<PagedResponse<User>> findUsersPaged(
            String keyword,
            AccountStatus status,
            Long minCredits,
            LocalDateTime createdStart,
            LocalDateTime createdEnd,
            LocalDateTime lastLoginStart,
            LocalDateTime lastLoginEnd,
            String sortBy,
            String sortDir,
            int page,
            int size) {
        // 构建查询条件
        Criteria combined = new Criteria();
        boolean hasAny = false;

        // 关键词：ID 精确匹配 或 用户名/邮箱/手机号 模糊匹配
        if (keyword != null && !keyword.trim().isEmpty()) {
            String trimmedKeyword = keyword.trim();
            
            // 检查是否为 MongoDB ObjectId 格式（24位十六进制字符）
            boolean isObjectId = trimmedKeyword.length() == 24 && trimmedKeyword.matches("[0-9a-fA-F]+");
            
            if (isObjectId) {
                // 可能是用户 ID，添加 ID 精确匹配
                String like = ".*" + java.util.regex.Pattern.quote(trimmedKeyword) + ".*";
                Criteria or = new Criteria().orOperator(
                        Criteria.where("_id").is(trimmedKeyword),  // ID 精确匹配
                        Criteria.where("username").regex(like, "i"),
                        Criteria.where("email").regex(like, "i"),
                        Criteria.where("phone").regex(like, "i")
                );
                combined = combined.andOperator(or);
            } else {
                // 普通关键词，只进行模糊匹配
                String like = ".*" + java.util.regex.Pattern.quote(trimmedKeyword) + ".*";
                Criteria or = new Criteria().orOperator(
                        Criteria.where("username").regex(like, "i"),
                        Criteria.where("email").regex(like, "i"),
                        Criteria.where("phone").regex(like, "i")
                );
                combined = combined.andOperator(or);
            }
            hasAny = true;
        }

        if (status != null) {
            combined = hasAny ? combined.andOperator(Criteria.where("accountStatus").is(status)) : Criteria.where("accountStatus").is(status);
            hasAny = true;
        }

        if (minCredits != null) {
            Criteria c = Criteria.where("credits").gte(minCredits);
            combined = hasAny ? combined.andOperator(c) : c;
            hasAny = true;
        }

        if (createdStart != null || createdEnd != null) {
            Criteria c = Criteria.where("createdAt");
            if (createdStart != null && createdEnd != null) {
                c = c.gte(createdStart).lte(createdEnd);
            } else if (createdStart != null) {
                c = c.gte(createdStart);
            } else {
                c = c.lte(createdEnd);
            }
            combined = hasAny ? combined.andOperator(c) : c;
            hasAny = true;
        }

        if (lastLoginStart != null || lastLoginEnd != null) {
            Criteria c = Criteria.where("lastLoginAt");
            if (lastLoginStart != null && lastLoginEnd != null) {
                c = c.gte(lastLoginStart).lte(lastLoginEnd);
            } else if (lastLoginStart != null) {
                c = c.gte(lastLoginStart);
            } else {
                c = c.lte(lastLoginEnd);
            }
            combined = hasAny ? combined.andOperator(c) : c;
            hasAny = true;
        }

        Query query = new Query();
        if (hasAny) {
            query.addCriteria(combined);
        }

        // 排序
        String sortField = (sortBy == null || sortBy.isBlank()) ? "createdAt" : sortBy;
        Sort.Direction direction = ("asc".equalsIgnoreCase(sortDir)) ? Sort.Direction.ASC : Sort.Direction.DESC;
        query.with(Sort.by(direction, sortField));

        // 分页
        Pageable pageable = PageRequest.of(Math.max(0, page), Math.max(1, Math.min(size, 200)));
        query.skip(pageable.getOffset());
        query.limit(pageable.getPageSize());

        Mono<List<User>> contentMono = mongoTemplate.find(query, User.class).collectList();

        // 统计总数
        Query countQuery = new Query();
        if (hasAny) {
            countQuery.addCriteria(combined);
        }
        Mono<Long> countMono = mongoTemplate.count(countQuery, User.class);

        return Mono.zip(contentMono, countMono)
                .map(tuple -> PagedResponse.of(tuple.getT1(), page, pageable.getPageSize(), tuple.getT2()));
    }

    @Override
    @Transactional
    public Mono<User> resetUserPassword(String id, String rawPassword) {
        if (rawPassword == null || rawPassword.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("新密码不能为空"));
        }
        final String encoded = passwordEncoder.encode(rawPassword.trim());
        return userRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + id)))
                .flatMap(user -> {
                    user.setPassword(encoded);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }

    @Override
    @Transactional
    public Mono<User> bumpUserTokenVersion(String userId) {
        return userRepository.findById(userId)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("用户不存在: " + userId)))
                .flatMap(user -> {
                    Integer v = user.getTokenVersion() == null ? 1 : user.getTokenVersion();
                    user.setTokenVersion(v + 1);
                    user.setUpdatedAt(LocalDateTime.now());
                    return userRepository.save(user);
                });
    }
}