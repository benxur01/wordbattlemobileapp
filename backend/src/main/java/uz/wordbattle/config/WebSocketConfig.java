package uz.wordbattle.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;
import uz.wordbattle.ws.GameSocketHandler;
import uz.wordbattle.ws.HandshakeAuthInterceptor;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    private final GameSocketHandler handler;
    private final HandshakeAuthInterceptor authInterceptor;
    private final AppProperties props;

    public WebSocketConfig(GameSocketHandler handler, HandshakeAuthInterceptor authInterceptor, AppProperties props) {
        this.handler = handler;
        this.authInterceptor = authInterceptor;
        this.props = props;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        var registration = registry.addHandler(handler, "/ws").addInterceptors(authInterceptor);
        // A phone client sends no Origin header, and Spring lets those through
        // whatever is configured here. Naming origins is therefore only about
        // browsers — so the wildcard goes away unless a web build asks for it.
        if (props.cors().enabled()) {
            registration.setAllowedOriginPatterns(props.cors().allowedOrigins().toArray(String[]::new));
        }
    }
}
