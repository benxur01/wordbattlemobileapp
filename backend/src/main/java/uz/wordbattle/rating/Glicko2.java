package uz.wordbattle.rating;

/**
 * Glicko-2 (Mark Glickman's specification), one match per rating period.
 *
 * <p>Ratings are stored on the familiar ~1500 scale and converted to the
 * internal scale (µ, φ) for the update, exactly as the paper describes.
 */
public final class Glicko2 {

    /** Scale factor between the display rating and the internal one. */
    private static final double SCALE = 173.7178;

    /** System constant: how much volatility can move. Lower = steadier. */
    private static final double TAU = 0.5;

    private static final double EPSILON = 0.000001;

    private Glicko2() {}

    public record Rating(double rating, double deviation, double volatility) {}

    public enum Outcome {
        WIN(1.0), LOSS(0.0), DRAW(0.5);

        final double score;

        Outcome(double score) {
            this.score = score;
        }
    }

    public static Rating update(Rating player, Rating opponent, Outcome outcome) {
        double mu = (player.rating() - 1500) / SCALE;
        double phi = player.deviation() / SCALE;
        double sigma = player.volatility();

        double muOpponent = (opponent.rating() - 1500) / SCALE;
        double phiOpponent = opponent.deviation() / SCALE;

        double g = g(phiOpponent);
        double expected = e(mu, muOpponent, phiOpponent);

        double v = 1.0 / (g * g * expected * (1 - expected));
        double delta = v * g * (outcome.score - expected);

        double sigmaPrime = newVolatility(phi, sigma, delta, v);
        double phiStar = Math.sqrt(phi * phi + sigmaPrime * sigmaPrime);
        double phiPrime = 1.0 / Math.sqrt(1.0 / (phiStar * phiStar) + 1.0 / v);
        double muPrime = mu + phiPrime * phiPrime * g * (outcome.score - expected);

        double newRating = SCALE * muPrime + 1500;
        double newDeviation = SCALE * phiPrime;

        // Keep the deviation inside sane bounds: never so small that a rating
        // freezes, never larger than a brand-new player's.
        newDeviation = Math.min(350, Math.max(30, newDeviation));
        return new Rating(newRating, newDeviation, sigmaPrime);
    }

    /**
     * Step 6 of the paper: the deviation a player who has not settled a rated
     * duel in a while should be carrying. Certainty decays — someone who left
     * on 60 is not still that well known a season later, and treating them as
     * if they were means both they and everyone they meet barely move.
     *
     * <p>{@code periodsElapsed} is fractional on purpose. The paper inflates
     * once per whole rating period because it settles a batch of games at a
     * time; duels here settle one at a time, at whatever moment they end, and
     * rounding that to whole periods would make the growth depend on when the
     * game happened to finish rather than on how long the player was away.
     *
     * <p>Clamped to the same 350 ceiling {@link #update} enforces, so no amount
     * of absence leaves a player less known than a brand-new account.
     */
    public static double inflateForInactivity(double deviation, double volatility, double periodsElapsed) {
        if (periodsElapsed <= 0) return deviation;
        double phi = deviation / SCALE;
        double phiStar = Math.sqrt(phi * phi + volatility * volatility * periodsElapsed);
        return Math.min(350, SCALE * phiStar);
    }

    private static double g(double phi) {
        return 1.0 / Math.sqrt(1 + 3 * phi * phi / (Math.PI * Math.PI));
    }

    private static double e(double mu, double muOpponent, double phiOpponent) {
        return 1.0 / (1 + Math.exp(-g(phiOpponent) * (mu - muOpponent)));
    }

    /** Illinois-algorithm root finding from the Glicko-2 paper, step 5. */
    private static double newVolatility(double phi, double sigma, double delta, double v) {
        double a = Math.log(sigma * sigma);
        double A = a;
        double B;

        double deltaSq = delta * delta;
        double phiSq = phi * phi;

        if (deltaSq > phiSq + v) {
            B = Math.log(deltaSq - phiSq - v);
        } else {
            int k = 1;
            while (f(a - k * TAU, deltaSq, phiSq, v, a) < 0) {
                k++;
                if (k > 100) break;
            }
            B = a - k * TAU;
        }

        double fA = f(A, deltaSq, phiSq, v, a);
        double fB = f(B, deltaSq, phiSq, v, a);

        int guard = 0;
        while (Math.abs(B - A) > EPSILON && guard++ < 100) {
            double C = A + (A - B) * fA / (fB - fA);
            double fC = f(C, deltaSq, phiSq, v, a);
            if (fC * fB <= 0) {
                A = B;
                fA = fB;
            } else {
                fA = fA / 2;
            }
            B = C;
            fB = fC;
        }
        return Math.exp(A / 2);
    }

    private static double f(double x, double deltaSq, double phiSq, double v, double a) {
        double ex = Math.exp(x);
        double num = ex * (deltaSq - phiSq - v - ex);
        double den = 2 * Math.pow(phiSq + v + ex, 2);
        return num / den - (x - a) / (TAU * TAU);
    }
}
