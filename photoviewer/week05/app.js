// ============================================================
// Photo Viewer — Stage 3
//
// Fetches the photo list from /photos — the dynamic API endpoint
// served by Flask on EC2 via ALB via CloudFront.
//
// Stage 1/2 fetched from /photos.json (static file in S3).
// Stage 3 onwards fetches from /photos (dynamic API).
// Everything else stays the same.
// ============================================================

let photos = [];
let currentIndex = 0;

async function loadPhotos() {
  try {
    const response = await fetch('/photos');
    photos = await response.json();
    if (photos.length > 0) {
      currentIndex = Math.floor(Math.random() * photos.length);
      showPhoto(currentIndex);
    }
  } catch (err) {
    console.error('Failed to load photo list:', err);
  }
}

function showPhoto(index) {
  const img = document.getElementById('photo');
  const counter = document.getElementById('counter');
  img.src = '/' + photos[index].s3_key;
  img.alt = photos[index].photo_id;
  counter.textContent = (index + 1) + ' of ' + photos.length;
}

function nextPhoto() {
  if (photos.length === 0) return;
  currentIndex = (currentIndex + 1) % photos.length;
  showPhoto(currentIndex);
}

loadPhotos();
