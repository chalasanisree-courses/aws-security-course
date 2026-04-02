// ============================================================
// Photo Viewer — Stage 1 + Stage 2
//
// Fetches the photo list from /photos.json — a static file
// served by S3 (Stage 1) or CloudFront (Stage 2).
//
// In Stage 3, the only change to this file will be replacing
// '/photos.json' with '/photos' — the dynamic API endpoint.
// Everything else stays the same.
// ============================================================

let photos = [];
let currentIndex = 0;

async function loadPhotos() {
  try {
    const response = await fetch('/photos.json');
    photos = await response.json();
    if (photos.length > 0) {
      // Start at a random photo rather than always photo-001
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

// Load the photo list when the page loads
loadPhotos();
