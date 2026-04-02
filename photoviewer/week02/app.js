// ============================================================
// Photo Viewer — Stage 1 + Stage 2 compatible
//
// Relative paths work in both stages:
//   Stage 1: S3 static website hosting resolves /photos/* against
//            the bucket root.
//   Stage 2: CloudFront resolves /photos/* against the S3 origin.
//            The browser never contacts S3 directly.
// ============================================================

const photos = [
  "/photos/photo1.jpg",
  "/photos/photo2.jpg",
  "/photos/photo3.jpg",
  "/photos/photo4.jpg",
  "/photos/photo5.jpg"
];

let currentIndex = 0;

function showPhoto(index) {
  const img = document.getElementById("photo");
  const counter = document.getElementById("counter");
  img.src = photos[index];
  img.alt = "Photo " + (index + 1);
  counter.textContent = (index + 1) + " of " + photos.length;
}

function nextPhoto() {
  currentIndex = (currentIndex + 1) % photos.length;
  showPhoto(currentIndex);
}

// Show the first photo when the page loads
showPhoto(currentIndex);
