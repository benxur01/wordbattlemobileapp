package uz.wordbattle.config;

import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import uz.wordbattle.auth.JwtAuthFilter;
import uz.wordbattle.auth.RestAuthEntryPoint;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;
    private final RestAuthEntryPoint authEntryPoint;
    private final AppProperties props;

    public SecurityConfig(JwtAuthFilter jwtAuthFilter, RestAuthEntryPoint authEntryPoint, AppProperties props) {
        this.jwtAuthFilter = jwtAuthFilter;
        this.authEntryPoint = authEntryPoint;
        this.props = props;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                // Stateless JWT API consumed by a mobile app: no cookies, so CSRF
                // protection has nothing to protect.
                .csrf(csrf -> csrf.disable())
                // Only when a browser origin is actually configured. Left off,
                // the API answers no cross-origin preflight at all — which is
                // what a phone-only backend wants.
                .cors(cors -> {
                    if (props.cors().enabled()) {
                        cors.configurationSource(corsSource());
                    } else {
                        cors.disable();
                    }
                })
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/auth/**", "/actuator/health/**", "/actuator/info").permitAll()
                        // The socket authenticates itself from the token in the
                        // query string during the handshake.
                        .requestMatchers("/ws/**").permitAll()
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(ex -> ex.authenticationEntryPoint(authEntryPoint))
                .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable());
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOriginPatterns(props.cors().allowedOrigins());
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
