package com.ainovel.server.common.util;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.mantoux.delta.Delta;
import org.mantoux.delta.OpList;
import org.mantoux.delta.Op;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

public class RichTextUtil {

    private static final Logger log = LoggerFactory.getLogger(RichTextUtil.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Extracts plain text from a Quill Delta object.
     *
     * @param delta Quill Delta object
     * @return Plain text string
     */
    public static String deltaToPlainText(Delta delta) {
        if (delta == null) {
            return "";
        }
        // Use the library's provided method to get plain text
        return delta.plainText();
    }

    /**
     * Extracts plain text from a Quill Delta JSON string.
     * Supports both standard Delta object format ("ops": [...]) and direct array format ([...]).
     * Falls back to HTML stripping and then plain text if JSON parsing fails.
     *
     * @param deltaJson Quill Delta JSON string, or HTML, or plain text
     * @return Plain text string
     */
    public static String deltaJsonToPlainText(String deltaJson) {
        if (deltaJson == null || deltaJson.trim().isEmpty()) {
            return "";
        }
        String trimmedJson = deltaJson.trim();

        try {
            // Attempt 1: Parse as standard Delta object {"ops": [...]}
            if (trimmedJson.startsWith("{") && trimmedJson.endsWith("}") && trimmedJson.contains("\"ops\"")) {
                try {
                    Delta delta = objectMapper.readValue(trimmedJson, Delta.class);
                    return deltaToPlainText(delta);
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 1: Failed to parse as standard Delta object ({{\"ops\":...}}). Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to try other parsing methods
                }
            }
            
            // Attempt 2: Parse as a JSON array of operations [...] using the library's Op and Delta classes
            if (trimmedJson.startsWith("[") && trimmedJson.endsWith("]")) {
                try {
                    List<Op> opJavaList = objectMapper.readValue(trimmedJson, new TypeReference<List<Op>>() {});
                    OpList opList = new OpList(opJavaList); // OpList constructor takes Collection<? extends Op>
                    Delta delta = new Delta(opList);
                    return deltaToPlainText(delta);
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 2: Failed to parse JSON array into List<Op>. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to manual map parsing as a robust fallback for arrays
                } catch (Exception e) { // Catch other exceptions like from OpList/Delta constructor or runtime issues
                     log.warn("Attempt 2: Failed to construct OpList/Delta from parsed List<Op>. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                     // Fall through to manual map parsing
                }

                // Attempt 3 (Fallback for array): Parse as List<Map<String, Object>> and extract inserts manually
                try {
                    List<Map<String, Object>> opsListRaw = objectMapper.readValue(trimmedJson, new TypeReference<List<Map<String, Object>>>() {});
                    StringBuilder sb = new StringBuilder();
                    for (Map<String, Object> opMap : opsListRaw) {
                        if (opMap.containsKey("insert")) {
                            Object insertValue = opMap.get("insert");
                            if (insertValue instanceof String) {
                                sb.append((String) insertValue);
                            } else if (insertValue instanceof Map) {
                                // Delta.plainText() typically adds a newline for embedded objects.
                                sb.append("\n"); 
                            }
                        }
                    }
                    // If opsListRaw was empty (trimmedJson was "[]"), sb will be empty, which is correct.
                    return sb.toString();
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 3 (Fallback): Failed to parse as JSON array of maps. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to HTML/plain text check if all Delta JSON parsing fails
                }
            }

            // Final Fallbacks: If not a recognized Delta JSON, try as HTML or plain text
            if (isHtml(trimmedJson)) {
                log.debug("Input not recognized as Delta JSON, attempting to strip HTML. Input snippet: {}", 
                          trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                return stripHtml(trimmedJson);
            }

//            log.debug("Input is not Delta JSON or HTML, returning as is. Input snippet: {}",
//                      trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
            return trimmedJson; // Assume plain text or unprocessable format

        } catch (Exception e) { // Catch any other unexpected exceptions during processing
            log.error("Unexpected error in deltaJsonToPlainText. Input snippet: {}. Error: {}. Details: {}", 
                      trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)), e.getMessage(), e.toString());
            // Fallback in case of any other error
            if (isHtml(trimmedJson)) {
                return stripHtml(trimmedJson);
            }
            return trimmedJson; // Final fallback
        }
    }

    /**
     * Basic HTML tag stripping.
     * For complex HTML, consider a dedicated library like JSoup.
     *
     * @param html HTML string
     * @return Text with HTML tags removed
     */
    private static String stripHtml(String html) {
        if (html == null) return "";
        String noHtml = html.replaceAll("<[^>]*>", "");
        // Basic HTML entity decoding
        noHtml = noHtml.replace("&nbsp;", " ")
                       .replace("&lt;", "<")
                       .replace("&gt;", ">")
                       .replace("&amp;", "&")
                       .replace("&quot;", "\"")
                       .replace("&apos;", "'");
        return noHtml;
    }

    /**
     * Basic check to see if a string might be HTML.
     *
     * @param text The string to check
     * @return true if the string heuristically looks like HTML, false otherwise
     */
    private static boolean isHtml(String text) {
        if (text == null) return false;
        String trimmedText = text.trim();
        // Simple heuristic: starts with <, ends with >, and contains at least one tag-like structure.
        return trimmedText.startsWith("<") && trimmedText.endsWith(">") && trimmedText.matches(".*<[^>]+>.*");
    }
} 
