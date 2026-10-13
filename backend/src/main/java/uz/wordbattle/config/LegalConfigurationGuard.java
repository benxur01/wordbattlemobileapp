package uz.wordbattle.config;

import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/** Refuses to serve placeholder legal contact details from a production deployment. */
@Component
public class LegalConfigurationGuard {

    public LegalConfigurationGuard(Environment environment, AppProperties props) {
        verify(
                props.legal().contactEmail(),
                props.legal().operatorName(),
                environment.acceptsProfiles(Profiles.of(DatabasePasswordGuard.PRODUCTION_PROFILE)));
    }

    static void verify(String contactEmail, String operatorName, boolean production) {
        if (!production) return;

        if (contactEmail == null || contactEmail.isBlank() || "support@example.uz".equalsIgnoreCase(contactEmail.trim())) {
            throw new IllegalStateException(
                    "LEGAL_CONTACT_EMAIL haqiqiy aloqa manziliga almashtirilishi kerak (production).");
        }
        if (operatorName == null || operatorName.isBlank() || "Word Battle".equalsIgnoreCase(operatorName.trim())) {
            throw new IllegalStateException(
                    "LEGAL_OPERATOR_NAME haqiqiy operatorning yuridik nomiga almashtirilishi kerak (production).");
        }
    }
}
