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

    // 日時を取得し、フォーマットする
    const now = new Date()
    const yyyy = now.getFullYear()
    const MM = String(now.getMonth() + 1).padStart(2, "0")
    const dd = String(now.getDate()).padStart(2, "0")
    const HH = String(now.getHours()).padStart(2, "0")
    const mm = String(now.getMinutes()).padStart(2, "0")
    const ss = String(now.getSeconds()).padStart(2, "0")
    const timestamp = `${yyyy}${MM}${dd}_${HH}${mm}${ss}`

    // ファイル名に日時を追加
    const newFileName = `${timestamp}_${file.name}`
    const blobUrl = `${containerUrl}/${encodeURIComponent(newFileName)}?${sasToken}`

    fetch(blobUrl, {
        method: "PUT",
        headers: {
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": file.type
        },
        body: file
    }).then(response => {
        if (response.ok) {
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
            const blobs = Array.from(xml.getElementsByTagName("Blob")) // NodeList → 配列

            // 名前を降順（新しいものが先）でソート
            blobs.sort((a, b) => {
                const nameA = a.getElementsByTagName("Name")[0].textContent
                const nameB = b.getElementsByTagName("Name")[0].textContent
                return nameB.localeCompare(nameA)
            })

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
