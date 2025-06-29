const containerUrl = "https://__STORAGE_ACCOUNT__.blob.core.windows.net/images"
const sasToken = "__SAS_TOKEN__".replace(/^\?/, "") // 先頭の?が二重になるのを防ぐ

document.getElementById("file").addEventListener("change", function () {
    const fileName = this.files[0] ? this.files[0].name : "No file chosen"
    document.getElementById("file-name").textContent = fileName
})

document.getElementById("upload-form").addEventListener("submit", function (e) {
    e.preventDefault()
    const file = document.getElementById("file").files[0]
    if (!file) return alert("ファイルを選んでください")

    const blobUrl = `${containerUrl}/${encodeURIComponent(file.name)}?${sasToken}`
    fetch(blobUrl, {
        method: "PUT",
        headers: {
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": file.type
        },
        body: file
    }).then(response => {
        if (response.ok) {
            // alert("アップロード成功")
            loadImages()
        } else {
            alert("アップロード失敗")
        }
    })
})

function loadImages() {
    const listUrl = `${containerUrl}?restype=container&comp=list&${sasToken}`
    fetch(listUrl)
        .then(res => res.text())
        .then(xmlText => {
            const parser = new DOMParser()
            const xml = parser.parseFromString(xmlText, "application/xml")
            const blobs = xml.getElementsByTagName("Blob")

            const grid = document.getElementById("image-grid")
            grid.innerHTML = ""

            for (let i = 0; i < blobs.length; i++) {
                const name = blobs[i].getElementsByTagName("Name")[0].textContent
                const url = `${containerUrl}/${encodeURIComponent(name)}?${sasToken}`

                const card = document.createElement("div")
                card.className = "image-card"

                const img = document.createElement("img")
                img.src = url
                img.alt = name
                img.className = "thumbnail-image"
                img.style.cursor = "pointer"

                img.addEventListener("click", function () {
                    const modalImage = document.getElementById("modalImage")
                    modalImage.src = url
                    $('#imageModal').modal('show')
                })

                card.appendChild(img)
                grid.appendChild(card)
            }
        })
}

document.addEventListener("DOMContentLoaded", function () {
    loadImages()
})
