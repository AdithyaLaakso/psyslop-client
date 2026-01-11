<script lang="ts">
import { onMount } from 'svelte';

interface Program {
  id: string;
  name: string;
  duration: number;
  description: string;
  start_time: number;
  end_time: number;
  normalized_duration?: number;
  truncated_right?: boolean;
  grid_column_start?: number;
}

interface Channel {
  id: string;
  number: number;
  name: string;
  description: string;
  updated_at?: number;
}

interface ChannelRow {
  channel: Channel;
  programs: Program[];
}

interface GuideData {
  rows: ChannelRow[];
  start_time: number;
  end_time: number;
}

function getTimeBlocks(
  start: string | Date | null,
  end: string | Date | null,
): string[] | null {
  if (start == null || end == null) {
    return null;
  }
  const result: string[] = [];

  let current = new Date(start);
  const endDate = new Date(end);

  while (current < endDate) {
    let d = new Date(current);
    result.push(
      d.getHours().toString().padStart(2, "0") +
      ":" +
      d.getMinutes().toString().padStart(2, "0")
    );
    current = new Date(current.getTime() + 30 * 60 * 1000); // +30 minutes
  }

  return result;
}

function normalizePrograms(data: GuideData): GuideData {
  const SLOT_DURATION = 30 * 60 * 1000; // 30 minutes in milliseconds

  const normalizedRows = data.rows.map(row => {
    const normalizedPrograms = row.programs.map(program => {
      // Calculate which time slot this program starts in (0-indexed)
      const startOffset = program.start_time - data.start_time;
      const gridColumnStart = Math.floor(startOffset / SLOT_DURATION);

      // Calculate how many 30-minute slots this program spans
      const programDuration = program.end_time - program.start_time;
      const normalized_duration = Math.max(1, Math.round(programDuration / SLOT_DURATION));

      return {
        ...program,
        grid_column_start: gridColumnStart,
        normalized_duration: normalized_duration
      };
    });

    return {
      ...row,
      programs: normalizedPrograms
    };
  });

  return {
    ...data,
    rows: normalizedRows
  };
}

async function init(): Promise<void> {
  try {
    const response = await fetch('https://api.psyslop.tv/guide');
    const data = await response.json();
    guideData = normalizePrograms(data);
    loading = false;
  } catch (err) {
    console.error('Failed to load guide data:', err);
    error = true;
    loading = false;
  }

  // Initialize video.js
  if (typeof window !== 'undefined' && (window as any).videojs) {
    const videoElement = document.getElementById('slop-player');
    if (videoElement) {
      videoPlayer = (window as any).videojs(videoElement, {
        controls: false,
        autoplay: true,
        preload: 'auto',
        fluid: true,
        sources: [{
          src: 'https://slop.sfo3.cdn.digitaloceanspaces.com/_long/08-01-2026.mp4',
          type: 'video/mp4'
        }],
        crossorigin: 'anonymous',
        muted: true,
      });
    }
  }
}

let guideData: GuideData | null = null;
let selectedChannel: number | null = null;
let loading = true;
let error = false;
let videoPlayer: any = null;
let isMuted = true;
let isFullscreen = false;

onMount(() => {
  init();
});

function selectChannel(channelNum: number) {
  selectedChannel = selectedChannel === channelNum ? null : channelNum;
}

function getChannelColor(num: number): string {
  const colors = ['#ff0000', '#0000ff', '#ffff00', '#ff6600', '#00ff00', '#ff00ff', '#ff1493', '#00ffff'];
  return colors[num % colors.length];
}

function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
}

function toggleMute() {
  if (videoPlayer) {
    isMuted = !isMuted;
    videoPlayer.muted(isMuted);
  }
}

function toggleFullscreen() {
  if (videoPlayer) {
    if (!isFullscreen) {
      videoPlayer.requestFullscreen();
      isFullscreen = true;
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen();
      }
      isFullscreen = false;
    }
  }
}

$: sortedChannels = guideData?.rows.sort((a, b) => a.channel.number - b.channel.number) || [];
$: timeBlocks = guideData
  ? getTimeBlocks(
      new Date(guideData.start_time),
      new Date(guideData.end_time)
    )
  : null;
$: numTimeSlots = timeBlocks?.length || 0;
</script>

<svelte:head>
  <link href="https://vjs.zencdn.net/8.10.0/video-js.css" rel="stylesheet" />
  <script src="https://vjs.zencdn.net/8.10.0/video.min.js"></script>
</svelte:head>

<div class="tv-guide">
  <!-- Header -->
  <div class="header">
    <div class="logo">SLOP GUIDE</div>
    <div class="date">LIVE NOW • {new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }).toUpperCase()}</div>
  </div>

  <!-- Video Player Section -->
  <div class="player-container">
    <video id="slop-player" class="video-js vjs-big-play-centered"></video>
    <div class="player-controls">
      <button class="control-btn" on:click={toggleMute}>
        {#if isMuted}
          🔇 UNMUTE
        {:else}
          🔊 MUTE
        {/if}
      </button>
      <button class="control-btn" on:click={toggleFullscreen}>
        ⛶ FULLSCREEN
      </button>
    </div>
  </div>

  {#if loading}
    <div class="loading">
      <div class="loading-text">LOADING SLOP GUIDE...</div>
      <div class="loading-bar"></div>
    </div>
  {:else if error}
    <div class="error">
      <div class="error-text">ERROR: UNABLE TO LOAD GUIDE</div>
      <div class="error-subtext">THE SLOP STREAM HAS BEEN INTERRUPTED</div>
    </div>
  {:else if guideData}
    <!-- Channel Listings -->
    <div class="listings">
      <div class="listings-header" style="grid-template-columns: 80px 200px repeat({numTimeSlots}, 1fr);">
        <div class="col-header">CH</div>
        <div class="col-header">NETWORK</div>
        {#if timeBlocks}
          {#each timeBlocks as tb}
            <div class="col-header time-header">{tb}</div>
          {/each}
        {/if}
      </div>

      <div class="listings-body">
        {#each sortedChannels as row (row.channel.id)}
          <div class="channel-container">
            <div
              class="listing-row"
              class:selected={selectedChannel === row.channel.number}
              on:click={() => selectChannel(row.channel.number)}
              on:keydown={() => {}}
              role="button"
              tabindex={row.channel.number}
              style="grid-template-columns: 80px 200px repeat({numTimeSlots}, 1fr);"
            >
              <div class="col-channel channel-num">{row.channel.number}</div>
              <div class="col-network">
                <span class="network-badge" style="background-color: {getChannelColor(row.channel.number)}">
                  {row.channel.name.split(':')[0]}
                </span>
              </div>

              <!-- Time slot cells with programs -->
              <div class="program-grid" style="grid-column: 3 / -1; display: grid; grid-template-columns: repeat({numTimeSlots}, 1fr); gap: 3px;">
                {#each row.programs as program}
                  {#if program.grid_column_start !== undefined && program.normalized_duration}
                    <div
                      class="program-block"
                      style="grid-column: {program.grid_column_start + 1} / span {program.normalized_duration};"
                    >
                      <div class="program-title">{program.name}</div>
                      <div class="program-time">{formatTime(program.start_time)} - {formatTime(program.end_time)}</div>
                    </div>
                  {/if}
                {/each}
              </div>
            </div>

            {#if selectedChannel === row.channel.number}
              <div class="expanded-info">
                <div class="channel-description">
                  <strong>CHANNEL INFO:</strong> {row.channel.name}
                </div>
                <div class="channel-description-full">
                  {row.channel.description}
                </div>
                {#if row.programs && row.programs.length > 0}
                  <div class="program-details">
                    <div class="program-header">NOW PLAYING:</div>
                    <div class="program-name">{row.programs[0].name}</div>
                    <div class="program-desc">{row.programs[0].description}</div>
                    <div class="program-duration">Duration: {row.programs[0].duration} minutes</div>
                  </div>
                {/if}
                {#if row.programs && row.programs.length > 1}
                  <div class="upcoming">
                    <div class="upcoming-header">UP NEXT:</div>
                    {#each row.programs.slice(1, 4) as program}
                      <div class="upcoming-item">
                        <span class="upcoming-time">{formatTime(program.start_time)}</span>
                        <span class="upcoming-name">{program.name}</span>
                      </div>
                    {/each}
                  </div>
                {/if}
                <div class="reminder-text">★ TUNE IN NOW • VIEWER DISCRETION ADVISED ★</div>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </div>
  {/if}

  <!-- Footer -->
  <div class="footer">
    <div class="footer-text">
      Click channel for details • All programming subject to slop conditions • Viewing may cause existential discomfort
    </div>
  </div>
</div>

<style>
:global(body) {
  margin: 0;
  padding: 0;
  background: #000;
  font-family: 'Courier New', monospace;
  color: #fff;
}

:global(.video-js) {
  width: 100%;
  height: 100%;
}

:global(.vjs-big-play-button) {
  display: none !important;
}

.tv-guide {
  width: 100%;
  background: #1a1a2e;
  min-height: 100vh;
}

.header {
  background: linear-gradient(180deg, #2a2a4e 0%, #1a1a2e 100%);
  padding: 20px 40px;
  border-bottom: 3px solid #ffcc00;
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
}

.logo {
  font-size: 36px;
  font-weight: bold;
  color: #ffcc00;
  text-shadow: 2px 2px 0px #00ff00, 4px 4px 0px #ff00ff;
  letter-spacing: 2px;
}

.date {
  font-size: 12px;
  color: #00ff00;
  background: #000;
  padding: 5px 10px;
  border: 2px solid #00ff00;
}

.player-container {
  position: relative;
  background: #000;
  border-bottom: 3px solid #ffcc00;
  aspect-ratio: 16 / 9;
}

.player-controls {
  position: absolute;
  bottom: 20px;
  right: 20px;
  display: flex;
  gap: 10px;
  z-index: 10;
}

.control-btn {
  background: rgba(0, 0, 0, 0.8);
  color: #ffcc00;
  border: 2px solid #ffcc00;
  padding: 10px 15px;
  font-family: 'Courier New', monospace;
  font-size: 14px;
  font-weight: bold;
  cursor: pointer;
  transition: all 0.2s;
}

.control-btn:hover {
  background: #ffcc00;
  color: #000;
  transform: scale(1.05);
}

.loading, .error {
  padding: 60px 20px;
  text-align: center;
}

.loading-text, .error-text {
  font-size: 24px;
  color: #ffcc00;
  margin-bottom: 20px;
}

.error-subtext {
  font-size: 14px;
  color: #ff0000;
}

.loading-bar {
  width: 200px;
  height: 4px;
  background: #333;
  margin: 20px auto;
  position: relative;
  overflow: hidden;
}

.loading-bar::after {
  content: '';
  position: absolute;
  width: 50%;
  height: 100%;
  background: #00ff00;
  animation: loading 1.5s infinite;
}

@keyframes loading {
  0% { left: -50%; }
  100% { left: 100%; }
}

.listings {
  background: #0a0a1e;
  padding: 0;
}

.listings-header {
  display: grid;
  padding: 15px 10px;
  background: #2a2a4e;
  border-bottom: 2px solid #ffcc00;
  font-weight: bold;
  color: #ffcc00;
  position: sticky;
  top: 0;
  z-index: 5;
  gap: 3px;
  min-width: 100%;
}

.col-header {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  min-width: 0;
}

.time-header {
  font-size: 12px;
  color: #ffcc00;
}

.listings-body {
  background: #0a0a1e;
  min-width: 100%;
}

.channel-container {
  border-bottom: 1px solid #333;
}

.listing-row {
  display: grid;
  padding: 10px;
  cursor: pointer;
  transition: background 0.2s;
  gap: 3px;
  min-height: 70px;
  align-items: center;
  min-width: 100%;
}

.listing-row:hover {
  background: #2a2a4e;
}

.listing-row.selected {
  background: #3a3a6e;
  border-left: 5px solid #00ff00;
}

.col-channel {
  display: flex;
  align-items: center;
  justify-content: center;
}

.channel-num {
  font-size: 32px;
  font-weight: bold;
  color: #00ffff;
}

.col-network {
  display: flex;
  align-items: center;
  justify-content: center;
}

.network-badge {
  display: inline-block;
  padding: 8px 12px;
  border: 2px solid #000;
  font-weight: bold;
  font-size: 11px;
  color: #000;
  text-shadow: 1px 1px 0px rgba(255, 255, 255, 0.5);
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.program-grid {
  position: relative;
  height: 100%;
  min-height: 60px;
  gap: 3px;
}

.program-block {
  border: 2px solid #ffcc00;
  border-radius: 4px;
  padding: 8px 10px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: center;
  transition: all 0.2s;
  height: 100%;
}

.program-title {
  font-size: 14px;
  font-weight: bold;
  color: #fff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-bottom: 4px;
}

.program-time {
  font-size: 11px;
  color: #00ff88;
  white-space: nowrap;
  font-weight: normal;
}

.expanded-info {
  background: #1a1a3e;
  padding: 25px;
  border-left: 5px solid #00ff00;
  border-bottom: 2px solid #ffcc00;
  animation: slideDown 0.3s ease-out;
  grid-column: 1 / -1;
}

@keyframes slideDown {
  from {
    opacity: 0;
    max-height: 0;
  }
  to {
    opacity: 1;
    max-height: 1000px;
  }
}

.channel-description {
  font-size: 16px;
  margin-bottom: 10px;
  color: #ffcc00;
}

.channel-description-full {
  font-size: 13px;
  line-height: 1.6;
  margin-bottom: 20px;
  color: #aaa;
  border-left: 3px solid #ffcc00;
  padding-left: 15px;
}

.program-details {
  background: rgba(0, 255, 0, 0.1);
  padding: 15px;
  margin: 15px 0;
  border: 2px solid #00ff00;
}

.program-header {
  font-size: 12px;
  color: #00ff00;
  margin-bottom: 8px;
}

.program-name {
  font-size: 20px;
  font-weight: bold;
  color: #fff;
  margin-bottom: 10px;
}

.program-desc {
  font-size: 14px;
  line-height: 1.5;
  margin-bottom: 10px;
  color: #ddd;
}

.program-duration {
  font-size: 12px;
  color: #ffcc00;
}

.upcoming {
  margin-top: 20px;
}

.upcoming-header {
  font-size: 14px;
  color: #ff00ff;
  margin-bottom: 10px;
  font-weight: bold;
}

.upcoming-item {
  padding: 8px 0;
  border-bottom: 1px solid #333;
  display: flex;
  gap: 15px;
}

.upcoming-time {
  color: #00ffff;
  font-size: 12px;
  min-width: 80px;
}

.upcoming-name {
  color: #fff;
  font-size: 14px;
}

.reminder-text {
  text-align: center;
  color: #ffcc00;
  font-size: 12px;
  margin-top: 20px;
  animation: blink 2s infinite;
}

@keyframes blink {
  0%, 50%, 100% { opacity: 1; }
  25%, 75% { opacity: 0.4; }
}

.footer {
  background: #2a2a4e;
  padding: 15px 40px;
  border-top: 3px solid #ffcc00;
  position: sticky;
  bottom: 0;
}

.footer-text {
  text-align: center;
  color: #00ff00;
  font-size: 12px;
}

@media (max-width: 968px) {
  .logo {
    font-size: 24px;
  }

  .date {
    font-size: 10px;
  }

  .channel-num {
    font-size: 24px;
  }

  .player-controls {
    bottom: 10px;
    right: 10px;
    flex-direction: column;
  }

  .control-btn {
    font-size: 11px;
    padding: 8px 12px;
  }
}
</style>
