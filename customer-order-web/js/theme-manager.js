/**
 * AlphaPos — Theme & Language Manager Module
 * Handles dark/light theme toggle, language switching, and UI translation.
 */
import { translations } from './i18n.js';

export const ThemeManagerMixin = {
    toggleTheme() {
        this.currentTheme = this.currentTheme === 'dark' ? 'light' : 'dark';
        localStorage.setItem('alphapos_theme', this.currentTheme);
        this.applyTheme();
    },

    applyTheme() {
        document.documentElement.setAttribute('data-theme', this.currentTheme);
        document.body.classList.toggle('light-theme', this.currentTheme === 'light');
        document.body.classList.toggle('dark-theme', this.currentTheme === 'dark');
    },

    switchLanguage(lang) {
        if (!['th', 'en', 'zh'].includes(lang)) return;
        this.currentLang = lang;
        localStorage.setItem('alphapos_lang', lang);
        this.translateUI();
        this.renderMenuItems();
        this.hideLangDropdown();

        // Update lang indicator
        const flagEl = document.getElementById('langCurrentFlag');
        const labelEl = document.getElementById('langCurrentLabel');
        const flags = { th: '🇹🇭', en: '🇬🇧', zh: '🇨🇳' };
        if (flagEl) flagEl.textContent = flags[lang] || '';
        if (labelEl) labelEl.textContent = lang.toUpperCase();
    },

    toggleLangDropdown(event) {
        if (event) event.stopPropagation();
        const menu = document.getElementById('langDropdownMenu');
        if (menu) menu.classList.toggle('active');
    },

    hideLangDropdown() {
        const menu = document.getElementById('langDropdownMenu');
        if (menu) menu.classList.remove('active');
    },

    translate(key, fallback = '') {
        const langDict = translations[this.currentLang] || translations['en'] || {};
        return langDict[key] || fallback || key;
    },

    translateUI() {
        // Translate all elements with data-translate-key attribute
        document.querySelectorAll('[data-translate-key]').forEach(el => {
            const key = el.getAttribute('data-translate-key');
            const translated = this.translate(key);
            if (translated && translated !== key) {
                el.textContent = translated;
            }
        });
    }
};
