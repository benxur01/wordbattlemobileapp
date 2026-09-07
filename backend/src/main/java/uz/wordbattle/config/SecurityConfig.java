package uz.wordbattle.config;

import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import uz.wordbattle.admin.AdminAuthFilter;
import uz.wordbattle.auth.AuthRateLimiter;
import uz.wordbattle.auth.JwtAuthFilter;
import uz.wordbattle.auth.RestAuthEntryPoint;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;
    private final AuthRateLimiter authRateLimiter;
    private final AdminAuthFilter adminAuthFilter;
    private final RestAuthEntryPoint authEntryPoint;
    private final RestAccessDeniedHandler accessDeniedHandler;
    private final AppProperties props;

    public SecurityConfig(
            JwtAuthFilter jwtAuthFilter,
            AuthRateLimiter authRateLimiter,
            AdminAuthFilter adminAuthFilter,
            RestAuthEntryPoint authEntryPoint,
            RestAccessDeniedHandler accessDeniedHandler,
            AppProperties props) {
        this.jwtAuthFilter = jwtAuthFilter;
        this.authRateLimiter = authRateLimiter;
        this.adminAuthFilter = adminAuthFilter;
        this.authEntryPoint = authEntryPoint;
        this.accessDeniedHandler = accessDeniedHandler;
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
                        // Android's Digital Asset Links verifier fetches this
                        // with no token at all — behind the catch-all below it
                        // would get a 401 and App Links verification would
                        // silently never succeed.
                        .requestMatchers("/.well-known/**").permitAll()
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        // Before the catch-all, or the catch-all would answer
                        // for it and every signed-in player would be an admin.
                        // The role is granted by AdminAuthFilter, to admins, on
                        // this path alone.
                        .requestMatchers("/api/admin/**").hasRole("ADMIN")
                        .anyRequest().authenticated())
                .exceptionHandling(ex -> ex.authenticationEntryPoint(authEntryPoint)
                        .accessDeniedHandler(accessDeniedHandler))
                .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
                // Ahead of everything that reads a token, because the routes it
                // guards are the ones nobody carries a token to: a refused
                // attempt is meant to cost this server a map lookup and not a
                // bcrypt comparison. Registered relative to JwtAuthFilter,
                // which the line above adds, so the two cannot be reordered.
                .addFilterBefore(authRateLimiter, JwtAuthFilter.class)
                // After the token has named a player, since that is what this
                // one looks the admin role up for. The position is expressed
                // relative to JwtAuthFilter, which the line above is what
                // registers — so the two calls cannot be reordered.
                .addFilterAfter(adminAuthFilter, JwtAuthFilter.class)
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable());
        return http.build();
    }

    /** Hashes the passwords chosen by players who register without Google. */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
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
