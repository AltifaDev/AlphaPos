export function showToast(message, durationOrOptions = 3000) {
    const toast = document.getElementById("toast");
    if (!toast) return;

    let duration = 3000;
    let type = "";
    if (typeof durationOrOptions === "number" && Number.isFinite(durationOrOptions)) {
        duration = durationOrOptions;
    } else if (typeof durationOrOptions === "string") {
        // Back-compat: callers sometimes pass a type label ('success') as the 2nd arg
        type = durationOrOptions;
        duration = 3000;
    } else if (durationOrOptions && typeof durationOrOptions === "object") {
        if (typeof durationOrOptions.duration === "number" && Number.isFinite(durationOrOptions.duration)) {
            duration = durationOrOptions.duration;
        }
        if (typeof durationOrOptions.type === "string") {
            type = durationOrOptions.type;
        }
    }

    toast.textContent = message;
    toast.className = type ? `toast show toast-${type}` : "toast show";
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
