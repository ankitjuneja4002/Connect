package com.connect.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service
@Slf4j
@RequiredArgsConstructor
public class EmailService {

    private final JavaMailSender javaMailSender;

    @Value("${spring.mail.username:}")
    private String mailUsername;

    @Value("${DEMO_MODE:false}")
    private String demoMode;
    
    // Log initialization to debug
    @jakarta.annotation.PostConstruct
    public void init() {
        log.info("EmailService initialized. mailUsername: {}, demoMode: {}, isEmailConfigured: {}", 
            mailUsername, demoMode, isEmailConfigured());
    }

    public void sendEmail(String to, String subject, String text) {
        // Always check demo mode first - if email not configured, skip sending
        if (!isEmailConfigured()) {
            String otp = extractOTPFromText(text);
            log.warn("DEMO MODE: Email not configured. Skipping email send.");
            log.info("DEMO MODE: Would send email to: {} | Subject: {} | OTP: {}", 
                to, subject, otp);
            log.info("DEMO MODE: OTP for {} is: {} (cached in Redis for 5 minutes)", to, otp);
            return; // Don't throw exception in demo mode
        }

        // If email is configured but demo mode is enabled, also skip
        if (isDemoMode()) {
            String otp = extractOTPFromText(text);
            log.warn("DEMO MODE: Enabled. Skipping email send.");
            log.info("DEMO MODE: OTP for {} is: {} (cached in Redis for 5 minutes)", to, otp);
            return;
        }

        // Try to send email only if email is properly configured
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setTo(to);
            message.setSubject(subject);
            message.setText(text);
            javaMailSender.send(message);
            log.info("Email sent successfully to: {}", to);
        } catch (Exception e) {
            log.error("Exception occurred while sending email: {}", e.getMessage());
            // If email send fails, log OTP and continue (don't fail signup)
            String otp = extractOTPFromText(text);
            log.warn("Email send failed. OTP for {}: {} (cached in Redis for 5 minutes)", to, otp);
            log.info("DEMO MODE: OTP for {} is: {} - Use this for verification", to, otp);
            // Don't throw exception - allow demo to continue
            return;
        }
    }

    private boolean isEmailConfigured() {
        return mailUsername != null && 
               !mailUsername.isEmpty() && 
               !mailUsername.equals("your-email@gmail.com");
    }

    private boolean isDemoMode() {
        // Check environment variable, system property, or if email is not configured
        String envDemoMode = System.getenv("DEMO_MODE");
        String sysDemoMode = System.getProperty("DEMO_MODE");
        
        return "true".equalsIgnoreCase(demoMode) || 
               "true".equalsIgnoreCase(envDemoMode) ||
               "true".equalsIgnoreCase(sysDemoMode) ||
               !isEmailConfigured(); // If email not configured, treat as demo mode
    }

    private String extractOTPFromText(String text) {
        // Extract OTP from email text (format: "Your OTP is: 123456" or "OTP is 1234")
        if (text != null) {
            // Try to find 4-digit OTP
            java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("\\b\\d{4}\\b");
            java.util.regex.Matcher matcher = pattern.matcher(text);
            if (matcher.find()) {
                return matcher.group();
            }
            // Try to find any sequence of digits
            pattern = java.util.regex.Pattern.compile("\\d+");
            matcher = pattern.matcher(text);
            if (matcher.find()) {
                String digits = matcher.group();
                // Return first 4-6 digits
                return digits.substring(0, Math.min(digits.length(), 6));
            }
        }
        return "N/A";
    }

}
