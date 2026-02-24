import { api, LightningElement } from 'lwc';
import { NavigationMixin } from "lightning/navigation";

export default class CustomLWRButton extends NavigationMixin(LightningElement) {
    @api variant;
    @api label;
    @api title;
    @api iconName;
    @api iconPosition;
    @api url;

    showPopup = false;
    isLoading = false;

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
        this.isLoading = true;
        setTimeout(() => {
            this.isLoading = false;
        }, 500);
    }

    endHover(e) {
        this.showPopup = false;
    }
}