package uz.wordbattle.ws;

import com.fasterxml.jackson.databind.JsonNode;

/** Every socket frame is {"type": "...", "payload": {...}}. */
public record Envelope(String type, JsonNode payload) {}
