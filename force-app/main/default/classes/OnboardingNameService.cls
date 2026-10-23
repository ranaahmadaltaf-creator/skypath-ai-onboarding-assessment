/** Deterministic searchable name, never exceeding the Salesforce 80-char limit. */
public without sharing class OnboardingNameService {
    public static String build(String customerName, Date launchDate) {
        String label = String.isBlank(customerName) ? 'Unknown Customer' : customerName.trim();
        String suffix = ' | Go Live: ' + toIsoDate(launchDate);
        Integer maxCustomerLength = 80 - suffix.length();
        if (label.length() > maxCustomerLength) {
            label = label.substring(0, maxCustomerLength);
        }
        return label + suffix;
    }

    private static String toIsoDate(Date d) {
        return String.valueOf(d.year()) + '-' + pad(d.month()) + '-' + pad(d.day());
    }

    private static String pad(Integer v) {
        return v < 10 ? '0' + String.valueOf(v) : String.valueOf(v);
    }
}
