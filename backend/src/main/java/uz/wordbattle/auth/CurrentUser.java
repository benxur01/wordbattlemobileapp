package uz.wordbattle.auth;

import java.lang.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

/** Injects the authenticated {@link AuthPrincipal} into a controller method. */
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@AuthenticationPrincipal
public @interface CurrentUser {}
