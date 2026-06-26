(function () {
  const STORAGE_KEY = "ffdc.playerRatings.v1";
  const ESPN_LATE_ADP_CUTOFF = 168.5;

  const data = window.DRAFT_DATA || { meta: {}, players: [] };
  const state = {
    search: "",
    leagueSize: 12,
    position: "ALL",
    status: "ALL",
    ratings: loadRatings(),
  };

  const elements = {
    board: document.querySelector("#board"),
    template: document.querySelector("#playerCardTemplate"),
    searchInput: document.querySelector("#searchInput"),
    leagueSize: document.querySelector("#leagueSize"),
    positionFilter: document.querySelector("#positionFilter"),
    statusFilter: document.querySelector("#statusFilter"),
    sourceMeta: document.querySelector("#sourceMeta"),
    playerCount: document.querySelector("#playerCount"),
    goodCount: document.querySelector("#goodCount"),
    badCount: document.querySelector("#badCount"),
    showGoodOnly: document.querySelector("#showGoodOnly"),
    showBadOnly: document.querySelector("#showBadOnly"),
    clearFilters: document.querySelector("#clearFilters"),
  };

  hydrateMeta();
  bindEvents();
  render();

  function bindEvents() {
    elements.searchInput.addEventListener("input", (event) => {
      state.search = event.target.value.trim().toLowerCase();
      render();
    });

    elements.leagueSize.addEventListener("change", (event) => {
      state.leagueSize = Number(event.target.value);
      render();
    });

    elements.positionFilter.addEventListener("change", (event) => {
      state.position = event.target.value;
      render();
    });

    elements.statusFilter.addEventListener("change", (event) => {
      state.status = event.target.value;
      render();
    });

    elements.showGoodOnly.addEventListener("click", () => {
      setStatusFilter("good");
    });

    elements.showBadOnly.addEventListener("click", () => {
      setStatusFilter("bad");
    });

    elements.clearFilters.addEventListener("click", () => {
      state.search = "";
      state.position = "ALL";
      setStatusFilter("ALL");
      elements.searchInput.value = "";
      elements.positionFilter.value = "ALL";
      render();
    });
  }

  function hydrateMeta() {
    const updatedAt = data.meta.updatedAt ? new Date(data.meta.updatedAt) : null;
    const updatedText = updatedAt
      ? updatedAt.toLocaleString([], {
          dateStyle: "medium",
          timeStyle: "short",
        })
      : "unknown update time";

    elements.sourceMeta.textContent = `${data.meta.rankType || "PPR"} rankings and ADP from ESPN fantasy data. Updated ${updatedText}.`;
  }

  function render() {
    const visiblePlayers = getVisiblePlayers();
    const grouped = groupByRound(visiblePlayers);

    elements.board.innerHTML = "";
    updateCounts(visiblePlayers);

    if (!visiblePlayers.length) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "No players match the current filters.";
      elements.board.append(empty);
      return;
    }

    grouped.forEach(([round, players]) => {
      const section = document.createElement("section");
      section.className = "round-section";

      const header = document.createElement("div");
      header.className = "round-header";
      const title = document.createElement("h2");
      title.textContent = round === "Later" ? "Later / Unranked" : `Round ${round}`;
      const details = document.createElement("span");
      details.textContent = `${players.length} players`;
      header.append(title, details);

      const grid = document.createElement("div");
      grid.className = "round-grid";
      players.forEach((player) => grid.append(createPlayerCard(player)));

      section.append(header, grid);
      elements.board.append(section);
    });
  }

  function getVisiblePlayers() {
    return data.players
      .map((player) => ({
        ...player,
        status: state.ratings[player.id] || "neutral",
      }))
      .filter((player) => {
        if (state.position !== "ALL" && player.position !== state.position) return false;
        if (state.status !== "ALL" && player.status !== state.status) return false;
        if (!state.search) return true;

        const haystack = `${player.name} ${player.team} ${player.position}`.toLowerCase();
        return haystack.includes(state.search);
      })
      .sort((a, b) => getSortValue(a) - getSortValue(b));
  }

  function groupByRound(players) {
    const grouped = new Map();

    players.forEach((player) => {
      const round = getRound(player);
      if (!grouped.has(round)) grouped.set(round, []);
      grouped.get(round).push(player);
    });

    return [...grouped.entries()].sort(([roundA], [roundB]) => {
      if (roundA === "Later") return 1;
      if (roundB === "Later") return -1;
      return Number(roundA) - Number(roundB);
    });
  }

  function createPlayerCard(player) {
    const node = elements.template.content.firstElementChild.cloneNode(true);
    const status = player.status;

    node.dataset.playerId = player.id;
    node.classList.toggle("good", status === "good");
    node.classList.toggle("bad", status === "bad");

    node.querySelector(".status-label").textContent = getStatusTitle(status);
    node.querySelector(".round-pick").textContent = getPickLabel(player);
    node.querySelector(".player-name").textContent = player.name;
    node.querySelector(".player-meta").textContent = `${player.position} - ${player.team}`;

    const photo = node.querySelector(".player-photo");
    const photoFallback = node.querySelector(".player-photo-fallback");
    photo.alt = player.position === "D/ST" ? `${player.name} logo` : `${player.name} headshot`;
    photoFallback.textContent = getPlayerInitials(player.name);
    photo.addEventListener("error", () => {
      photo.hidden = true;
      photoFallback.classList.add("visible");
    }, { once: true });
    photo.src = getPlayerImageUrl(player);

    node.querySelector(".espn-rank").textContent = formatRank(player.espnRank);
    node.querySelector(".espn-adp").textContent = formatNumber(player.adp);
    node.querySelector(".position-rank").textContent = player.positionRank || "-";

    node.querySelector(".good-button").addEventListener("click", () => setRating(player.id, "good"));
    node.querySelector(".bad-button").addEventListener("click", () => setRating(player.id, "bad"));
    node.querySelector(".clear-button").addEventListener("click", () => setRating(player.id, "neutral"));

    return node;
  }

  function getPlayerImageUrl(player) {
    if (player.position === "D/ST") {
      return `https://a.espncdn.com/i/teamlogos/nfl/500/${player.team.toLowerCase()}.png`;
    }

    return `https://a.espncdn.com/i/headshots/nfl/players/full/${player.id}.png`;
  }

  function getPlayerInitials(name) {
    return name
      .replace(" D/ST", "")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0])
      .join("")
      .toUpperCase();
  }

  function setRating(playerId, rating) {
    if (rating === "neutral") {
      delete state.ratings[playerId];
    } else {
      state.ratings[playerId] = rating;
    }

    saveRatings();
    render();
  }

  function setStatusFilter(status) {
    state.status = status;
    elements.statusFilter.value = status;
    render();
  }

  function updateCounts(visiblePlayers) {
    const allPlayers = data.players.map((player) => state.ratings[player.id] || "neutral");
    elements.playerCount.textContent = visiblePlayers.length.toString();
    elements.goodCount.textContent = allPlayers.filter((status) => status === "good").length.toString();
    elements.badCount.textContent = allPlayers.filter((status) => status === "bad").length.toString();
  }

  function getRound(player) {
    const draftValue = getDraftValue(player);
    if (!Number.isFinite(draftValue.value)) return "Later";
    return Math.max(1, Math.ceil(draftValue.value / state.leagueSize));
  }

  function getPickLabel(player) {
    const round = getRound(player);
    if (round === "Later") return "Later";

    const draftValue = getDraftValue(player);
    const label = draftValue.source === "board" ? `Board ${draftValue.value}` : `Pick ${Math.round(draftValue.value)}`;
    return `R${round} / ${label}`;
  }

  function getSortValue(player) {
    const draftValue = getDraftValue(player);
    if (Number.isFinite(draftValue.value)) return draftValue.value;
    return { value: Number.NaN, source: "none" };
  }

  function getDraftValue(player) {
    if (Number.isFinite(player.adp) && player.adp < ESPN_LATE_ADP_CUTOFF) {
      return { value: player.adp, source: "adp" };
    }

    if (Number.isFinite(player.boardRank)) {
      return { value: player.boardRank, source: "board" };
    }

    if (Number.isFinite(player.espnRank)) {
      return { value: player.espnRank, source: "board" };
    }

    return 9999;
  }

  function getStatusTitle(status) {
    if (status === "good") return "Good Pick";
    if (status === "bad") return "Bad Pick";
    return "Unmarked";
  }

  function formatRank(value) {
    return Number.isFinite(value) ? `#${value}` : "-";
  }

  function formatNumber(value) {
    return Number.isFinite(value) ? value.toFixed(1) : "-";
  }

  function loadRatings() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
    } catch {
      return {};
    }
  }

  function saveRatings() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state.ratings));
  }
})();
