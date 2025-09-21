package com.ainovel.server.service.impl;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ainovel.server.domain.model.SystemConfig;
import com.ainovel.server.domain.model.SystemConfig.ConfigType;
import com.ainovel.server.repository.SystemConfigRepository;
import com.ainovel.server.service.SystemConfigService;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * 系统配置服务实现
 */
@Service
public class SystemConfigServiceImpl implements SystemConfigService {
    
    private final SystemConfigRepository systemConfigRepository;
    
    @Autowired
    public SystemConfigServiceImpl(SystemConfigRepository systemConfigRepository) {
        this.systemConfigRepository = systemConfigRepository;
    }
    
    @Override
    @Transactional
    public Mono<SystemConfig> createConfig(SystemConfig config) {
        return systemConfigRepository.existsByConfigKey(config.getConfigKey())
                .flatMap(exists -> {
                    if (exists) {
                        return Mono.error(new IllegalArgumentException("配置键已存在: " + config.getConfigKey()));
                    }
                    
                    config.setCreatedAt(LocalDateTime.now());
                    config.setUpdatedAt(LocalDateTime.now());
                    
                    return systemConfigRepository.save(config);
                });
    }
    
    @Override
    @Transactional
    public Mono<SystemConfig> updateConfig(String id, SystemConfig config) {
        return systemConfigRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("配置不存在: " + id)))
                .flatMap(existingConfig -> {
                    if (existingConfig.getReadOnly() != null && existingConfig.getReadOnly()) {
                        return Mono.error(new IllegalArgumentException("只读配置不能修改: " + existingConfig.getConfigKey()));
                    }
                    
                    // 验证配置值
                    if (!existingConfig.isValidValue(config.getConfigValue())) {
                        return Mono.error(new IllegalArgumentException("配置值无效: " + config.getConfigValue()));
                    }
                    
                    existingConfig.setConfigValue(config.getConfigValue());
                    existingConfig.setDescription(config.getDescription());
                    existingConfig.setEnabled(config.getEnabled());
                    existingConfig.setUpdatedAt(LocalDateTime.now());
                    
                    return systemConfigRepository.save(existingConfig);
                });
    }
    
    @Override
    @Transactional
    public Mono<Void> deleteConfig(String id) {
        return systemConfigRepository.findById(id)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("配置不存在: " + id)))
                .flatMap(config -> {
                    if (config.getReadOnly() != null && config.getReadOnly()) {
                        return Mono.error(new IllegalArgumentException("只读配置不能删除: " + config.getConfigKey()));
                    }
                    return systemConfigRepository.deleteById(id);
                });
    }
    
    @Override
    public Mono<SystemConfig> getConfig(String configKey) {
        return systemConfigRepository.findByConfigKey(configKey);
    }
    
    @Override
    public Mono<String> getConfigValue(String configKey) {
        return getConfig(configKey)
                .map(SystemConfig::getConfigValue)
                .switchIfEmpty(Mono.empty());
    }
    
    @Override
    public Mono<String> getStringValue(String configKey, String defaultValue) {
        return getConfigValue(configKey)
                .switchIfEmpty(defaultValue != null ? Mono.just(defaultValue) : Mono.empty());
    }
    
    @Override
    public Mono<Double> getNumericValue(String configKey, Double defaultValue) {
        return getConfig(configKey)
                .map(SystemConfig::getNumericValue)
                .switchIfEmpty(defaultValue != null ? Mono.just(defaultValue) : Mono.empty());
    }
    
    @Override
    public Mono<Integer> getIntegerValue(String configKey, Integer defaultValue) {
        return getConfig(configKey)
                .map(SystemConfig::getIntegerValue)
                .switchIfEmpty(defaultValue != null ? Mono.just(defaultValue) : Mono.empty());
    }
    
    @Override
    public Mono<Long> getLongValue(String configKey, Long defaultValue) {
        return getConfig(configKey)
                .map(SystemConfig::getLongValue)
                .switchIfEmpty(defaultValue != null ? Mono.just(defaultValue) : Mono.empty());
    }
    
    @Override
    public Mono<Boolean> getBooleanValue(String configKey, Boolean defaultValue) {
        return getConfig(configKey)
                .map(SystemConfig::getBooleanValue)
                .switchIfEmpty(defaultValue != null ? Mono.just(defaultValue) : Mono.empty());
    }
    
    @Override
    @Transactional
    public Mono<Boolean> setConfigValue(String configKey, String value) {
        return systemConfigRepository.findByConfigKey(configKey)
                .switchIfEmpty(Mono.error(new IllegalArgumentException("配置不存在: " + configKey)))
                .flatMap(config -> {
                    if (config.getReadOnly() != null && config.getReadOnly()) {
                        return Mono.error(new IllegalArgumentException("只读配置不能修改: " + configKey));
                    }
                    
                    if (!config.isValidValue(value)) {
                        return Mono.error(new IllegalArgumentException("配置值无效: " + value));
                    }
                    
                    config.setConfigValue(value);
                    config.setUpdatedAt(LocalDateTime.now());
                    
                    return systemConfigRepository.save(config);
                })
                .thenReturn(true)
                .onErrorReturn(false);
    }
    
    @Override
    @Transactional
    public Mono<Boolean> setConfigValues(Map<String, String> configs) {
        return Flux.fromIterable(configs.entrySet())
                .flatMap(entry -> setConfigValue(entry.getKey(), entry.getValue()))
                .all(result -> result);
    }
    
    @Override
    public Flux<SystemConfig> findAll() {
        return systemConfigRepository.findAll();
    }
    
    @Override
    public Flux<SystemConfig> findByGroup(String configGroup) {
        return systemConfigRepository.findByConfigGroup(configGroup);
    }
    
    @Override
    public Flux<SystemConfig> findByType(ConfigType configType) {
        return systemConfigRepository.findByConfigType(configType);
    }
    
    @Override
    public Flux<SystemConfig> findAllEnabled() {
        return systemConfigRepository.findByEnabledTrue();
    }
    
    @Override
    public Flux<SystemConfig> findAllNonReadOnly() {
        return systemConfigRepository.findByReadOnlyFalse();
    }
    
    @Override
    @Transactional
    public Mono<Boolean> initializeDefaultConfigs() {
        List<SystemConfig> defaultConfigs = List.of(
            SystemConfig.builder()
                    .configKey(SystemConfig.Keys.CREDIT_TO_USD_RATE)
                    .configValue("100000")
                    .description("积分与美元的汇率（1美元等于多少积分）")
                    .configType(ConfigType.NUMBER)
                    .configGroup("credit")
                    .enabled(true)
                    .readOnly(false)
                    .defaultValue("100000")
                    .minValue("1000")
                    .maxValue("1000000")
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build(),
            
            SystemConfig.builder()
                    .configKey(SystemConfig.Keys.NEW_USER_CREDITS)
                    .configValue("200")
                    .description("新用户注册赠送的积分数量")
                    .configType(ConfigType.NUMBER)
                    .configGroup("credit")
                    .enabled(true)
                    .readOnly(false)
                    .defaultValue("200")
                    .minValue("0")
                    .maxValue("100000")
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build(),
            
            SystemConfig.builder()
                    .configKey(SystemConfig.Keys.DEFAULT_USER_ROLE)
                    .configValue("ROLE_FREE")
                    .description("新用户默认角色")
                    .configType(ConfigType.STRING)
                    .configGroup("user")
                    .enabled(true)
                    .readOnly(false)
                    .defaultValue("ROLE_FREE")
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build(),
            
            SystemConfig.builder()
                    .configKey(SystemConfig.Keys.ENABLE_USER_REGISTRATION)
                    .configValue("true")
                    .description("是否开启用户注册")
                    .configType(ConfigType.BOOLEAN)
                    .configGroup("user")
                    .enabled(true)
                    .readOnly(false)
                    .defaultValue("true")
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build(),
            
            SystemConfig.builder()
                    .configKey(SystemConfig.Keys.MAX_CONCURRENT_AI_REQUESTS)
                    .configValue("50")
                    .description("系统最大并发AI请求数")
                    .configType(ConfigType.NUMBER)
                    .configGroup("ai")
                    .enabled(true)
                    .readOnly(false)
                    .defaultValue("50")
                    .minValue("1")
                    .maxValue("1000")
                    .createdAt(LocalDateTime.now())
                    .updatedAt(LocalDateTime.now())
                    .build()
        );
        
        return Flux.fromIterable(defaultConfigs)
                .filterWhen(config -> 
                    systemConfigRepository.existsByConfigKey(config.getConfigKey())
                            .map(exists -> !exists)
                )
                .flatMap(systemConfigRepository::save)
                .then(Mono.just(true))
                .onErrorReturn(false);
    }
    
    @Override
    public Mono<Boolean> existsByConfigKey(String configKey) {
        return systemConfigRepository.existsByConfigKey(configKey);
    }
    
    @Override
    public Mono<Boolean> validateConfigValue(String configKey, String value) {
        return getConfig(configKey)
                .map(config -> config.isValidValue(value))
                .defaultIfEmpty(false);
    }
}