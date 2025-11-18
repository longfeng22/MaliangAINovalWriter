package com.ainovel.server.service.impl;

import java.security.Key;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.User;
import com.ainovel.server.service.JwtService;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import javax.crypto.SecretKey;

/**
 * JWT服务实现类
 */
@Service
public class JwtServiceImpl implements JwtService {
    
    @Value("${jwt.secret:defaultSecretKey12345678901234567890}")
    private String secretKey;
    
    @Value("${jwt.expiration:86400000}") // 默认24小时
    private long jwtExpiration;
    
    @Value("${jwt.refresh-expiration:604800000}") // 默认7天
    private long refreshExpiration;
    
    @Override
    public String generateToken(User user) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("userId", user.getId());
        claims.put("roles", user.getRoles() != null ? user.getRoles() : new ArrayList<>());
        return generateToken(claims, user, jwtExpiration);
    }
    
    @Override
    public String generateTokenWithRolesAndPermissions(User user, List<String> roles, List<String> permissions) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("userId", user.getId());
        claims.put("roles", roles != null ? roles : new ArrayList<>());
        claims.put("permissions", permissions != null ? permissions : new ArrayList<>());
        return generateToken(claims, user, jwtExpiration);
    }
    
    @Override
    public String generateRefreshToken(User user) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("userId", user.getId());
        return generateToken(claims, user, refreshExpiration);
    }
    
    private String generateToken(Map<String, Object> extraClaims, User user, long expiration) {
        // 增强：为后续可撤销性预置 jti，并将 tokenVersion 固定为用户当前版本
        extraClaims.putIfAbsent("jti", java.util.UUID.randomUUID().toString());
        Integer currentUserTokenVersion = user.getTokenVersion() == null ? 1 : user.getTokenVersion();
        // 强制覆盖，以保证新签发的token与用户当前版本一致
        extraClaims.put("tokenVersion", currentUserTokenVersion);
        return Jwts.builder()
                .setClaims(extraClaims)
                .setSubject(user.getUsername())
                .setIssuedAt(new Date(System.currentTimeMillis()))
                .setExpiration(new Date(System.currentTimeMillis() + expiration))
                .signWith(getSigningKey(), SignatureAlgorithm.HS256)
                .compact();
    }
    
    @Override
    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }
    
    @Override
    public String extractUserId(String token) {
        return extractClaim(token, claims -> claims.get("userId", String.class));
    }
    
    @Override
    @SuppressWarnings("unchecked")
    public List<String> extractRoles(String token) {
        List<String> roles = extractClaim(token, claims -> claims.get("roles", List.class));
        return roles != null ? roles : new ArrayList<>();
    }
    
    @Override
    @SuppressWarnings("unchecked")
    public List<String> extractPermissions(String token) {
        List<String> permissions = extractClaim(token, claims -> claims.get("permissions", List.class));
        return permissions != null ? permissions : new ArrayList<>();
    }
    
    @Override
    public boolean validateToken(String token, User user) {
        final String username = extractUsername(token);
        if (!username.equals(user.getUsername())) {
            return false;
        }
        if (isTokenExpired(token)) {
            return false;
        }
        // 关键校验：tokenVersion 必须与用户当前版本一致
        try {
            Integer tokenVersion = extractTokenVersion(token);
            Integer userVersion = user.getTokenVersion() == null ? 1 : user.getTokenVersion();
            if (tokenVersion == null) tokenVersion = 1;
            return tokenVersion.equals(userVersion);
        } catch (Exception ignore) {
            // 无法解析时，保守处理为无效
            return false;
        }
    }
    
    @Override
    public boolean isTokenExpired(String token) {
        return extractExpiration(token).before(new Date());
    }
    
    @Override
    public Date extractExpiration(String token) {
        return extractClaim(token, Claims::getExpiration);
    }

    @Override
    public String extractJti(String token) {
        try {
            return extractClaim(token, claims -> claims.getId());
        } catch (Exception ignore) {
            // 兼容通过claims字段存入的jti
            return extractClaim(token, claims -> claims.get("jti", String.class));
        }
    }

    @Override
    public Integer extractTokenVersion(String token) {
        Integer v = extractClaim(token, claims -> claims.get("tokenVersion", Integer.class));
        return v != null ? v : 1;
    }
    
    private <T> T extractClaim(String token, Function<Claims, T> claimsResolver) {
        final Claims claims = extractAllClaims(token);
        return claimsResolver.apply(claims);
    }
    
    private Claims extractAllClaims(String token) {
        return Jwts.parser()
                .verifyWith((SecretKey) getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
    
    private Key getSigningKey() {
        byte[] keyBytes = secretKey.getBytes();
        return Keys.hmacShaKeyFor(keyBytes);
    }
    
    // 保留旧私有方法的功能由接口方法替代
} 