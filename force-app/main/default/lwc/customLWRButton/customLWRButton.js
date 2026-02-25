import { api, LightningElement } from 'lwc';
import { NavigationMixin } from "lightning/navigation";

export default class CustomLWRButton extends NavigationMixin(LightningElement) {
    @api variant;
    @api label;
    @api title;
    @api iconName;
    @api iconPosition;
    @api url;

    get _variant() {
        const styleMap = {
            'Primary':   'brand',
            'Secondary': 'brand-outline',
            'Tertiary':  'base'
        };
        return styleMap[this.variant] || 'brand';
    }

    showPopup = false;

    get urlSlug() {
        return this.url.split('article/')[1];
    }

    handleNavigate() {
        this[NavigationMixin.GenerateUrl]({
            type: "standard__webPage",
            attributes: {
                url: this.url
            }
        }).then(url => {
            window.open(url, "_self");
        });
    }

    handleHover(e) {
        this.showPopup = true;
        this.timeout = setTimeout(() => {
            this.template.querySelector('.slds-popover')?.classList.remove('hidden');
        }, 300);
    }

    endHover(e) {
        clearTimeout(this.timeout);
        this.showPopup = false;
    }
}