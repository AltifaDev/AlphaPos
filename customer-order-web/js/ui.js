export function showToast(message, duration = 3000) {
    const toast = document.getElementById("toast");
    if (!toast) return;
    toast.textContent = message;
    toast.className = "toast show";
    setTimeout(() => {
        toast.className = "toast";
    }, duration);
}

export function showStatusModal(title, desc, isSuccess = false) {
    const modal = document.getElementById("statusModal");
    const spinner = document.getElementById("statusModalSpinner");
    const successIcon = document.getElementById("statusModalSuccessIcon");
    const titleEl = document.getElementById("statusModalTitle");
    const descEl = document.getElementById("statusModalDesc");

    if (!modal || !spinner || !successIcon || !titleEl || !descEl) return;

    titleEl.innerText = title;
    descEl.innerText = desc;

    if (isSuccess) {
        spinner.classList.add("hide");
        successIcon.classList.remove("hide");
    } else {
        spinner.classList.remove("hide");
        successIcon.classList.add("hide");
    }

    modal.classList.remove("hide");
    modal.offsetHeight;
    modal.classList.add("show");
}

export function hideStatusModal() {
    const modal = document.getElementById("statusModal");
    if (!modal) return;
    modal.classList.remove("show");
    setTimeout(() => {
        modal.classList.add("hide");
    }, 350);
}
