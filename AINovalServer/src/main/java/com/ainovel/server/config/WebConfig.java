package com.ainovel.server.config;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.CacheControl;
import org.springframework.web.reactive.config.EnableWebFlux;
import org.springframework.web.reactive.config.ResourceHandlerRegistry;
import org.springframework.web.reactive.config.WebFluxConfigurer;
import org.springframework.web.reactive.result.method.annotation.ArgumentResolverConfigurer;

import com.ainovel.server.security.CurrentUserMethodArgumentResolver ;

/**
 * WebFlux配置 用于配置参数解析器、跨域、静态资源等
 */
@Configuration
@EnableWebFlux
public class WebConfig implements WebFluxConfigurer {

    private final CurrentUserMethodArgumentResolver currentUserResolver;

    @Autowired
    public WebConfig(CurrentUserMethodArgumentResolver currentUserResolver) {
        this.currentUserResolver = currentUserResolver;
    }

    @Override
    public void configureArgumentResolvers(ArgumentResolverConfigurer configurer) {
        configurer.addCustomResolver(currentUserResolver);
    }
    
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        // 静态资源配置：映射前端静态文件到 /app/web/ 目录
        // 注意：不要拦截 /api/** 路径，避免影响API请求
        registry.addResourceHandler(
                "/",
                "/index.html",
                "/assets/**",
                "/icons/**",
                "/canvaskit/**",
                "/*.js",
                "/*.json",
                "/*.css",
                "/favicon.ico"
        )
                .addResourceLocations("file:/app/web/")
                .setCacheControl(CacheControl.noCache())
                .resourceChain(true);
    }
}
