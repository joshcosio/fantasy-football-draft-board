(function () {
  const STORAGE_KEY = "ffdc.playerRatings.v1";
  const ESPN_LATE_ADP_CUTOFF = 168.5;
  const TEAM_POSITIONS = ["QB", "RB", "WR", "TE", "K"];
  const PLAYER_PROFILER_SLUG_OVERRIDES = {
    4432708: "marvin-harrison-2",
  };

  const data = window.DRAFT_DATA || { meta: {}, players: [] };
  const teamData = window.TEAM_CHANGES || { meta: {}, teams: {} };
  const state = {
    search: "",
    leagueSize: 12,
    position: "ALL",
    status: "ALL",
    ratings: loadRatings(),
    activeTeam: null,
    activePlayer: null,
    teamMovementFilters: {
      joined: true,
      returning: true,
      departed: true,
    },
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
    teamDialog: document.querySelector("#teamDialog"),
    teamDialogClose: document.querySelector("#teamDialogClose"),
    teamDialogLogo: document.querySelector("#teamDialogLogo"),
    teamDialogSeason: document.querySelector("#teamDialogSeason"),
    teamDialogTitle: document.querySelector("#teamDialogTitle"),
    teamDialogSummary: document.querySelector("#teamDialogSummary"),
    teamDepthChart: document.querySelector("#teamDepthChart"),
    teamDataMeta: document.querySelector("#teamDataMeta"),
    teamEspnLink: document.querySelector("#teamEspnLink"),
    movementFilters: document.querySelectorAll(".movement-filter-input"),
    injuryDialog: document.querySelector("#injuryDialog"),
    injuryDialogClose: document.querySelector("#injuryDialogClose"),
    injuryDialogPhoto: document.querySelector("#injuryDialogPhoto"),
    injuryDialogTitle: document.querySelector("#injuryDialogTitle"),
    injuryDialogMeta: document.querySelector("#injuryDialogMeta"),
    injuryDialogStatus: document.querySelector("#injuryDialogStatus"),
    injuryDialogDate: document.querySelector("#injuryDialogDate"),
    injuryFacts: document.querySelector("#injuryFacts"),
    injuryType: document.querySelector("#injuryType"),
    injuryReturn: document.querySelector("#injuryReturn"),
    injuryReport: document.querySelector("#injuryReport"),
    injuryReportDate: document.querySelector("#injuryReportDate"),
    injuryShortComment: document.querySelector("#injuryShortComment"),
    injuryEmpty: document.querySelector("#injuryEmpty"),
    injuryEmptyTitle: document.querySelector("#injuryEmptyTitle"),
    injuryEmptyMessage: document.querySelector("#injuryEmptyMessage"),
    injuryDataMeta: document.querySelector("#injuryDataMeta"),
    injuryHistoryLink: document.querySelector("#injuryHistoryLink"),
    injuryEspnLink: document.querySelector("#injuryEspnLink"),
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

    elements.teamDialogClose.addEventListener("click", closeTeamDialog);
    elements.teamDialog.addEventListener("click", (event) => {
      if (event.target === elements.teamDialog) closeTeamDialog();
    });
    elements.teamDialog.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        closeTeamDialog();
      }
    });
    elements.teamDialog.addEventListener("close", () => {
      state.activeTeam = null;
      document.body.classList.remove("modal-open");
    });

    elements.movementFilters.forEach((filter) => {
      filter.addEventListener("change", (event) => {
        state.teamMovementFilters[event.target.value] = event.target.checked;
        if (state.activeTeam) renderTeamDialog(state.activeTeam);
      });
    });

    elements.injuryDialogClose.addEventListener("click", closeInjuryDialog);
    elements.injuryDialog.addEventListener("click", (event) => {
      if (event.target === elements.injuryDialog) closeInjuryDialog();
    });
    elements.injuryDialog.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        closeInjuryDialog();
      }
    });
    elements.injuryDialog.addEventListener("close", () => {
      state.activePlayer = null;
      document.body.classList.remove("modal-open");
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

    elements.sourceMeta.textContent = `ESPN live draft rank and ADP from fantasy data. Updated ${updatedText}.`;
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
    const playerMeta = node.querySelector(".player-meta");
    playerMeta.append(document.createTextNode(`${player.position} - `));
    if (teamData.teams[player.team]) {
      const teamButton = document.createElement("button");
      teamButton.className = "team-button";
      teamButton.type = "button";
      teamButton.textContent = player.team;
      teamButton.setAttribute("aria-label", `View ${player.team} offseason changes`);
      teamButton.addEventListener("click", () => openTeamDialog(player.team));
      playerMeta.append(teamButton);
    } else {
      playerMeta.append(document.createTextNode(player.team));
    }

    const injuryTag = node.querySelector(".injury-tag");
    if (player.position === "D/ST") {
      injuryTag.hidden = true;
    } else {
      const injuryStatus = getInjuryStatusInfo(player.injuryStatus);
      injuryTag.classList.add(injuryStatus.tone);
      injuryTag.querySelector(".injury-status-text").textContent = injuryStatus.label;
      injuryTag.setAttribute("aria-label", `View ${player.name} injury report: ${injuryStatus.label}`);
      injuryTag.addEventListener("click", () => openInjuryDialog(player));
    }

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

  function openInjuryDialog(player) {
    state.activePlayer = player.id;
    renderInjuryDialog(player);
    document.body.classList.add("modal-open");
    elements.injuryDialog.showModal();
  }

  function renderInjuryDialog(player) {
    const status = getInjuryStatusInfo(player.injuryStatus);
    const report = player.injuryReport;
    const hasCurrentInjury = isCurrentInjuryStatus(player.injuryStatus);
    const hasReport = Boolean(report && (hasCurrentInjury || report.type));

    elements.injuryDialogPhoto.src = getPlayerImageUrl(player);
    elements.injuryDialogPhoto.alt = `${player.name} headshot`;
    elements.injuryDialogTitle.textContent = player.name;
    elements.injuryDialogMeta.textContent = `${player.position} - ${player.team} - ${player.positionRank || "Unranked"}`;
    elements.injuryDialogStatus.className = `injury-status-badge ${status.tone}`;
    elements.injuryDialogStatus.textContent = status.label;
    elements.injuryDialogDate.textContent = hasReport && report?.date
      ? `Report updated ${formatDate(report.date)}`
      : hasCurrentInjury ? "No dated ESPN injury report" : "Current ESPN designation";

    elements.injuryFacts.hidden = !hasReport;
    elements.injuryReport.hidden = !hasReport;
    elements.injuryEmpty.hidden = hasReport;

    if (hasReport) {
      elements.injuryType.textContent = formatInjuryType(report);
      elements.injuryReturn.textContent = report.returnDate ? formatDate(report.returnDate) : "Not listed";
      elements.injuryReportDate.dateTime = report.date || "";
      elements.injuryReportDate.textContent = report.date ? formatDate(report.date) : "Date unavailable";
      elements.injuryShortComment.textContent = report.headline || "ESPN lists an injury report without an additional update.";
    } else if (hasCurrentInjury) {
      elements.injuryEmptyTitle.textContent = "Injury details unavailable";
      elements.injuryEmptyMessage.textContent = "ESPN flags this player with an injury designation, but its current feed does not include the underlying report.";
    } else {
      elements.injuryEmptyTitle.textContent = "No current injury report";
      elements.injuryEmptyMessage.textContent = "ESPN currently lists this player as active. PlayerProfiler provides the player's prior-season injury history.";
    }

    const injuryUpdatedAt = data.meta.injuryUpdatedAt ? formatDate(data.meta.injuryUpdatedAt) : "an unknown date";
    elements.injuryDataMeta.textContent = hasReport
      ? `${report.source || "ESPN"} via ESPN injury feed - updated ${injuryUpdatedAt}`
      : `ESPN injury feed updated ${injuryUpdatedAt}`;
    elements.injuryHistoryLink.href = getPlayerProfilerInjuryUrl(player);
    elements.injuryEspnLink.href = report?.newsUrl || getEspnPlayerNewsUrl(player);
  }

  function closeInjuryDialog() {
    if (elements.injuryDialog.open) elements.injuryDialog.close();
  }

  function openTeamDialog(teamAbbreviation) {
    const team = teamData.teams[teamAbbreviation];
    if (!team) return;

    state.activeTeam = teamAbbreviation;
    renderTeamDialog(teamAbbreviation);

    document.body.classList.add("modal-open");
    elements.teamDialog.showModal();
  }

  function renderTeamDialog(teamAbbreviation) {
    const team = teamData.teams[teamAbbreviation];
    if (!team) return;

    const currentSeason = teamData.meta.currentSeason || 2026;
    const previousSeason = teamData.meta.previousSeason || currentSeason - 1;
    const movementCounts = getTeamMovementCounts(team, state.teamMovementFilters);

    elements.teamDialogLogo.src = team.logo;
    elements.teamDialogLogo.alt = `${team.name} logo`;
    elements.teamDialogSeason.textContent = `${previousSeason} to ${currentSeason} fantasy roster changes`;
    elements.teamDialogTitle.textContent = team.name;
    elements.teamDialogSummary.textContent = `Showing ${movementCounts.joined} joined, ${movementCounts.departed} departed, ${movementCounts.returning} returning`;
    elements.teamEspnLink.href = team.espnDepthChart;
    elements.teamDepthChart.innerHTML = "";
    syncMovementFilters();

    TEAM_POSITIONS.forEach((position) => {
      const positionData = team.positions[position] || { current: [], departed: [] };
      elements.teamDepthChart.append(createDepthPosition(position, filterPositionData(positionData), currentSeason));
    });

    const updatedAt = teamData.meta.updatedAt ? new Date(teamData.meta.updatedAt) : null;
    const updatedText = updatedAt
      ? updatedAt.toLocaleDateString([], { dateStyle: "medium" })
      : "unknown date";
    elements.teamDataMeta.textContent = `ESPN fantasy data updated ${updatedText}`;
  }

  function closeTeamDialog() {
    if (elements.teamDialog.open) elements.teamDialog.close();
  }

  function getTeamMovementCounts(team, filters) {
    return TEAM_POSITIONS.reduce((counts, position) => {
      const positionData = team.positions[position] || { current: [], departed: [] };
      if (filters.joined) {
        counts.joined += positionData.current.filter((player) => player.status === "joined").length;
      }
      if (filters.returning) {
        counts.returning += positionData.current.filter((player) => player.status === "returning").length;
      }
      if (filters.departed) counts.departed += positionData.departed.length;
      return counts;
    }, { joined: 0, returning: 0, departed: 0 });
  }

  function filterPositionData(positionData) {
    return {
      current: positionData.current.filter((player) => state.teamMovementFilters[player.status]),
      departed: state.teamMovementFilters.departed ? positionData.departed : [],
    };
  }

  function syncMovementFilters() {
    elements.movementFilters.forEach((filter) => {
      filter.checked = state.teamMovementFilters[filter.value];
    });
  }

  function createDepthPosition(position, positionData, currentSeason) {
    const section = document.createElement("section");
    section.className = "depth-position";

    const header = document.createElement("header");
    const title = document.createElement("h3");
    title.textContent = position;
    const count = document.createElement("span");
    count.textContent = `${positionData.current.length} current`;
    header.append(title, count);

    const columns = document.createElement("div");
    columns.className = "depth-columns";
    columns.append(
      createDepthGroup(`${currentSeason} depth`, positionData.current, true),
      createDepthGroup("Departed", positionData.departed, false),
    );

    section.append(header, columns);
    return section;
  }

  function createDepthGroup(titleText, players, showRank) {
    const group = document.createElement("div");
    group.className = "depth-group";

    const title = document.createElement("h4");
    title.textContent = titleText;
    group.append(title);

    if (!players.length) {
      const empty = document.createElement("p");
      empty.className = "depth-empty";
      empty.textContent = titleText === "Departed" ? "No listed departures" : "No ESPN-listed players";
      group.append(empty);
      return group;
    }

    const list = document.createElement("ol");
    list.className = "depth-list";
    players.forEach((player, index) => list.append(createMovementRow(player, showRank ? index + 1 : null)));
    group.append(list);
    return group;
  }

  function createMovementRow(player, depthRank) {
    const item = document.createElement("li");
    item.className = `movement-row ${player.status}`;

    const rank = document.createElement("span");
    rank.className = "depth-rank";
    rank.textContent = depthRank || "OUT";

    const identity = document.createElement("div");
    const name = document.createElement("strong");
    name.textContent = player.name;
    const detail = document.createElement("small");
    detail.textContent = player.detail;
    identity.append(name, detail);

    const status = document.createElement("span");
    status.className = "movement-status";
    status.textContent = player.status === "joined"
      ? "Joined"
      : player.status === "departed" ? "Departed" : "Returning";

    item.append(rank, identity, status);
    return item;
  }

  function getPlayerImageUrl(player) {
    if (player.position === "D/ST") {
      return `https://a.espncdn.com/i/teamlogos/nfl/500/${player.team.toLowerCase()}.png`;
    }

    return `https://a.espncdn.com/i/headshots/nfl/players/full/${player.id}.png`;
  }

  function getEspnPlayerNewsUrl(player) {
    const slug = player.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    return `https://www.espn.com/nfl/player/news/_/id/${player.id}/${slug}`;
  }

  function getPlayerProfilerInjuryUrl(player) {
    const slug = PLAYER_PROFILER_SLUG_OVERRIDES[player.id] || player.name
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/\s+(Jr\.?|Sr\.?|II|III|IV)$/i, "")
      .toLowerCase()
      .replace(/['\u2019]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    return `https://www.playerprofiler.com/nfl/${slug}/#playerPageInjuryHistory`;
  }

  function getInjuryStatusInfo(value) {
    const status = (value || "UNKNOWN").toUpperCase();
    const labels = {
      ACTIVE: "Healthy",
      QUESTIONABLE: "Questionable",
      DOUBTFUL: "Doubtful",
      OUT: "Out",
      INJURY_RESERVE: "Injured Reserve",
      INJURED_RESERVE: "Injured Reserve",
      PUP: "PUP",
      SUSPENSION: "Suspended",
      UNKNOWN: "Status unknown",
    };

    let tone = "unknown";
    if (status === "ACTIVE") tone = "healthy";
    if (["QUESTIONABLE", "DOUBTFUL", "PUP"].includes(status)) tone = "injured";
    if (["OUT", "INJURY_RESERVE", "INJURED_RESERVE"].includes(status)) tone = "out";

    return { label: labels[status] || toTitleCase(status), tone };
  }

  function isCurrentInjuryStatus(value) {
    const status = (value || "").toUpperCase();
    return Boolean(status && !["ACTIVE", "SUSPENSION"].includes(status));
  }

  function formatInjuryType(report) {
    const side = report.side && report.side !== "Not Specified" ? `${report.side} ` : "";
    const type = report.type || report.location || "Not listed";
    const detail = report.detail && report.detail !== "Not Specified" ? ` (${report.detail})` : "";
    return `${side}${type}${detail}`;
  }

  function formatDate(value) {
    const dateOnly = typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
    const date = new Date(dateOnly ? `${value}T12:00:00` : value);
    if (Number.isNaN(date.getTime())) return "Unknown date";
    return date.toLocaleDateString([], { dateStyle: "medium" });
  }

  function toTitleCase(value) {
    return value
      .toLowerCase()
      .replace(/_/g, " ")
      .replace(/\b\w/g, (letter) => letter.toUpperCase());
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
    const label = draftValue.source === "board" ? `Rank ${draftValue.value}` : `ADP ${formatNumber(draftValue.value)}`;
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

    return { value: 9999, source: "none" };
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
