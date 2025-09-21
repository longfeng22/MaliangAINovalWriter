package com.ainovel.server.web.controller;

import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

/**
 * 静态资源控制器
 * 处理根路径和前端静态文件的访问
 */
@RestController
public class StaticResourceController {

    /**
     * 处理根路径请求，返回 index.html
     */
    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public Mono<Resource> index() {
        Resource resource = new FileSystemResource("/app/web/index.html");
        if (resource.exists()) {
            return Mono.just(resource);
        }
        return Mono.empty();
    }
    
    /**
     * 处理直接访问 index.html 的请求
     */
    @GetMapping(value = "/index.html", produces = MediaType.TEXT_HTML_VALUE)
    public Mono<Resource> indexHtml() {
        return index();
    }
}


