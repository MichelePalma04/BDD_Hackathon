--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

-- Started on 2025-11-24 12:58:11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 273 (class 1255 OID 57621)
-- Name: accetta_invito_giudice(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.accetta_invito_giudice(p_idutente integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_invitoEsiste INT;
    v_nuovoIdGiudice INT;
	v_idGiudiceEsistente INT;
BEGIN
    SELECT 1 INTO v_invitoEsiste
    FROM Invito
    WHERE idUtente = p_idUtente AND idEvento = p_idEvento AND stato IS NULL;

    IF v_invitoEsiste IS NULL THEN
        RAISE EXCEPTION 'L''invito non è valido o è già stato gestito.';
    END IF;

	SELECT idGiudice INTO v_idGiudiceEsistente
    FROM Giudice
    WHERE idUtente = p_idUtente;

    IF v_idGiudiceEsistente IS NULL THEN
        INSERT INTO Giudice (idUtente)
        VALUES (p_idUtente)
        RETURNING idGiudice INTO v_nuovoIdGiudice;
    ELSE
        v_nuovoIdGiudice := v_idGiudiceEsistente;
    END IF;

	UPDATE Invito
    SET stato = 'Accettato'
    WHERE idUtente = p_idUtente AND idEvento = p_idEvento;
	
    INSERT INTO Giudica (idGiudice, idEvento)
    VALUES (v_nuovoIdGiudice, p_idEvento);

    RETURN 'Invito accettato. Utente promosso a giudice per l''evento.';
END;
$$;


ALTER FUNCTION public.accetta_invito_giudice(p_idutente integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 283 (class 1255 OID 57631)
-- Name: assegna_voto_team_unico(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.assegna_voto_team_unico(p_idgiudice integer, p_idteam integer, p_valore integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idEvento INT;
    v_voto_esistente BOOLEAN;
BEGIN
    SELECT T.idEvento INTO v_idEvento
    FROM Team T
    WHERE T.idTeam = p_idTeam;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Il Team % non è valido o non è associato ad alcun Evento.', p_idTeam;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM Vota
        WHERE idGiudice = p_idGiudice AND idTeam = p_idTeam
    ) INTO v_voto_esistente;

    IF v_voto_esistente THEN
        RAISE EXCEPTION 'Il Giudice % ha già espresso il voto per il Team % e non può votare nuovamente o aggiornare il voto.', p_idGiudice, p_idTeam;
    END IF;

    IF NOT EXISTS (
        SELECT 1 
        FROM Giudica G 
        WHERE G.idGiudice = p_idGiudice AND G.idEvento = v_idEvento
    ) THEN
        RAISE EXCEPTION 'Il Giudice % non è assegnato all''Evento %.', p_idGiudice, v_idEvento;
    END IF;
    
    INSERT INTO Vota (idGiudice, idTeam, valore)
    VALUES (p_idGiudice, p_idTeam, p_valore);

    RETURN 'Voto ' || p_valore || ' inserito con successo per il Team ' || p_idTeam || ' (Evento ' || v_idEvento || ').';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante l''assegnazione del voto: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.assegna_voto_team_unico(p_idgiudice integer, p_idteam integer, p_valore integer) OWNER TO postgres;

--
-- TOC entry 281 (class 1255 OID 57629)
-- Name: carica_documento_team(integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.carica_documento_team(p_idpartecipante integer, p_idevento integer, p_pathdoc text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idTeamAssociato INT;
BEGIN
    SELECT T.idTeam INTO v_idTeamAssociato
    FROM Appartenenza A JOIN Team T ON A.idTeam = T.idTeam
    WHERE A.idPartecipante = p_idPartecipante AND T.idEvento = p_idEvento;
	
    IF v_idTeamAssociato IS NULL THEN
        RAISE EXCEPTION 'Errore: Il partecipante % non fa parte di nessun Team per l''Evento %.', p_idPartecipante, p_idEvento;
    END IF;

    INSERT INTO Documento (pathDoc, dataDoc, idTeam)
    VALUES (p_pathDoc, NOW(), v_idTeamAssociato);

    RETURN 'Documento "' || p_pathDoc || '" caricato con successo per il Team ' || v_idTeamAssociato || '.';

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Errore: Il documento con questo percorso è già stato caricato.';
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Errore di integrità: Dati non validi.';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante il caricamento: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.carica_documento_team(p_idpartecipante integer, p_idevento integer, p_pathdoc text) OWNER TO postgres;

--
-- TOC entry 259 (class 1255 OID 57588)
-- Name: check_assegnazione_team(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_assegnazione_team() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_giaInUnTeam INT;
    v_idEventoPartecipante INT;
    v_idEventoTeam INT;
	v_dataInizioEvento DATE;
BEGIN
    SELECT idEvento INTO v_idEventoTeam
    FROM Team
    WHERE idTeam = NEW.idTeam;

    SELECT idEvento INTO v_idEventoPartecipante
    FROM Partecipazione
    WHERE idPartecipante = NEW.idPartecipante AND idEvento = v_idEventoTeam;

    IF v_idEventoPartecipante IS NULL THEN
        RAISE EXCEPTION 'Errore di integrità: Il partecipante non è iscritto all''evento % ed è quindi incompatibile.', v_idEventoTeam;
	END IF;

	SELECT dataInizio INTO v_dataInizioEvento
    FROM Evento
    WHERE idEvento = v_idEventoTeam;
	
	IF CURRENT_DATE >= v_dataInizioEvento THEN
        RAISE EXCEPTION 'Impossibile assegnare il Team. L''Evento % è già iniziato il %.', v_idEventoTeam, v_dataInizioEvento;
    END IF;

	SELECT COUNT(*) INTO v_giaInUnTeam
    FROM Appartenenza A JOIN Team T ON A.idTeam = T.idTeam
    WHERE A.idPartecipante = NEW.idPartecipante AND T.idEvento = v_idEventoTeam
          AND A.idTeam <> NEW.idTeam;

    IF v_giaInUnTeam > 0 THEN
        RAISE EXCEPTION 'Errore: Il partecipante fa già parte di un team per questo evento.';
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_assegnazione_team() OWNER TO postgres;

--
-- TOC entry 265 (class 1255 OID 57608)
-- Name: check_commento_periodo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_commento_periodo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_data_upload TIMESTAMP;
    v_data_fine_evento DATE;
BEGIN
    SELECT D.dataDoc, E.dataFine INTO v_data_upload, v_data_fine_evento
    FROM Documento D JOIN Team T ON D.idTeam = T.idTeam JOIN Evento E ON T.idEvento = E.idEvento 
    WHERE D.idDocumento = NEW.idDocumento;

    IF v_data_fine_evento IS NULL THEN
        RAISE EXCEPTION 'Errore: Impossibile trovare i limiti temporali per l''Evento associato al Documento %.', NEW.idDocumento;
    END IF;

    IF CURRENT_TIMESTAMP < v_data_upload THEN
        RAISE EXCEPTION 'Non è possibile commentare un documento prima che sia stato caricato (Data/Ora Upload: %).', v_data_upload;
    END IF;

    IF CURRENT_DATE > v_data_fine_evento THEN
        RAISE EXCEPTION 'Non è possibile commentare. L''Evento è terminato il %.', v_data_fine_evento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_commento_periodo() OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 57578)
-- Name: check_eta_minima_utente(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_eta_minima_utente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 	IF NEW.dataNascita > CURRENT_DATE - INTERVAL '14 years' THEN
        RAISE EXCEPTION 'L''utente deve avere almeno 14 anni per essere registrato.';
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_eta_minima_utente() OWNER TO postgres;

--
-- TOC entry 241 (class 1255 OID 57586)
-- Name: check_evento_futuro_dinamico(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_evento_futuro_dinamico() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.inizioReg <= CURRENT_DATE THEN
        RAISE EXCEPTION 'La data di Inizio Registrazione (%) deve essere successiva alla data odierna (%).', NEW.inizioReg, CURRENT_DATE;
    END IF;

    IF NEW.dataInizio <= CURRENT_DATE THEN
        RAISE EXCEPTION 'La data di Inizio Evento (%) deve essere successiva alla data odierna (%).', NEW.dataInizio, CURRENT_DATE;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_evento_futuro_dinamico() OWNER TO postgres;

--
-- TOC entry 266 (class 1255 OID 57610)
-- Name: check_invito_giudica(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_invito_giudica() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idUtente INT;
    v_invito_accettato INT;
BEGIN
    SELECT idUtente INTO v_idUtente
    FROM Giudice
    WHERE idGiudice = NEW.idGiudice;

    SELECT 1 INTO v_invito_accettato
    FROM Invito
    WHERE idUtente = v_idUtente AND idEvento = NEW.idEvento AND stato = 'Accettato'
    LIMIT 1;

    IF v_invito_accettato IS NULL THEN
        RAISE EXCEPTION 'Non è possibile creare un collegamento in Giudica. È richiesto un invito accettato dall''utente per l''Evento %.', NEW.idEvento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_invito_giudica() OWNER TO postgres;

--
-- TOC entry 261 (class 1255 OID 57594)
-- Name: check_invito_precondizioni(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_invito_precondizioni() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_giudice INT;
    v_gia_giudice INT;
    v_idUtenteOrganizzatore INT;
    v_isPartecipante INT;
	v_dataNascita DATE;
BEGIN
	SELECT dataNascita INTO v_dataNascita
    FROM Utente
    WHERE idUtente = NEW.idUtente;

    IF v_dataNascita IS NULL OR v_dataNascita > CURRENT_DATE - INTERVAL '18 years' THEN
        RAISE EXCEPTION 'L''utente invitato (ID %) non ha l''età minima di 18 anni per essere Giudice.', NEW.idUtente;
    END IF;
	
    SELECT O.idUtente INTO v_idUtenteOrganizzatore
    FROM Organizzatore O JOIN Evento E ON O.idOrganizzatore = E.idOrganizzatore
    WHERE E.idEvento = NEW.idEvento;

    IF v_idUtenteOrganizzatore = NEW.idUtente THEN
        RAISE EXCEPTION 'Un organizzatore non può invitare sé stesso come giudice del proprio evento.';
    END IF;
    
    SELECT 1 INTO v_isPartecipante
    FROM Partecipazione PA JOIN Partecipante P ON PA.idPartecipante = P.idPartecipante
    WHERE P.idUtente = NEW.idUtente AND PA.idEvento = NEW.idEvento
    LIMIT 1;

    IF v_isPartecipante IS NOT NULL THEN
        RAISE EXCEPTION 'L''utente (ID %) è già partecipante all''evento (ID %) e non può essere invitato come giudice.', NEW.idUtente, NEW.idEvento;
    END IF;
    
    SELECT idGiudice INTO v_id_giudice
    FROM Giudice
    WHERE idUtente = NEW.idUtente;

    IF v_id_giudice IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT 1 INTO v_gia_giudice
    FROM Giudica
    WHERE idGiudice = v_id_giudice AND idEvento = NEW.idEvento
    LIMIT 1;

    IF v_gia_giudice IS NOT NULL THEN
        RAISE EXCEPTION 'L''utente (ID %) è già un Giudice assegnato per l''evento (ID %). Impossibile inviare un nuovo invito.', NEW.idUtente, NEW.idEvento;
    END IF;


	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_invito_precondizioni() OWNER TO postgres;

--
-- TOC entry 260 (class 1255 OID 57592)
-- Name: check_invito_prima_inizio(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_invito_prima_inizio() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_dataInizio DATE;
BEGIN
    SELECT dataInizio INTO v_dataInizio
    FROM Evento
    WHERE idEvento = NEW.idEvento;

    IF NOT FOUND THEN
         RAISE EXCEPTION 'Errore di integrità: L''evento (ID %) non esiste.', NEW.idEvento;
    END IF;

    IF CURRENT_DATE >= v_dataInizio THEN
        RAISE EXCEPTION 'Non è più possibile invitare giudici. L''evento è già iniziato il %.', v_dataInizio;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_invito_prima_inizio() OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 57596)
-- Name: check_iscrizione_apertura(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_iscrizione_apertura() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inizio_registrazioni DATE;
    v_fine_registrazioni DATE;
BEGIN
    SELECT inizioReg, fineReg INTO v_inizio_registrazioni, v_fine_registrazioni
    FROM Evento
    WHERE idEvento = NEW.idEvento;

    IF v_inizio_registrazioni IS NULL OR v_fine_registrazioni IS NULL THEN
        RAISE EXCEPTION 'Errore di sistema: Date di registrazione non definite per l''evento %.', NEW.idEvento;
    END IF;

    IF CURRENT_DATE < v_inizio_registrazioni THEN
        RAISE EXCEPTION 'Le registrazioni non sono ancora aperte. L''iscrizione è possibile solo a partire dal %.', v_inizio_registrazioni;
    END IF;

    IF CURRENT_DATE > v_fine_registrazioni THEN
        RAISE EXCEPTION 'Le registrazioni per questo evento sono già chiuse dal %.', v_fine_registrazioni;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_iscrizione_apertura() OWNER TO postgres;

--
-- TOC entry 285 (class 1255 OID 57598)
-- Name: check_iscrizione_ruoli(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_iscrizione_ruoli() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_idUtenteCorrente INT;
    v_idUtenteOrganizzatore INT;
    v_isGiudiceEffettivo INT;
BEGIN
	SELECT idUtente INTO v_idUtenteCorrente
    FROM Partecipante
    WHERE idPartecipante = NEW.idPartecipante;

    SELECT O.idUtente INTO v_idUtenteOrganizzatore
    FROM Organizzatore O JOIN Evento E ON O.idOrganizzatore = E.idOrganizzatore
    WHERE E.idEvento = NEW.idEvento;

    IF v_idUtenteOrganizzatore = v_idUtenteCorrente THEN
        RAISE EXCEPTION 'L''organizzatore non può iscriversi come partecipante al proprio evento.';
    END IF;

    SELECT 1 INTO v_isGiudiceEffettivo
    FROM Giudica G JOIN Giudice J ON G.idGiudice = J.idGiudice
    WHERE J.idUtente = v_idUtenteCorrente AND G.idEvento = NEW.idEvento
    LIMIT 1;

    IF v_isGiudiceEffettivo IS NOT NULL THEN
        RAISE EXCEPTION 'L''utente con ID % è già un giudice effettivo per l''evento % e non può iscriversi come partecipante.', v_idUtenteCorrente, NEW.idEvento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_iscrizione_ruoli() OWNER TO postgres;

--
-- TOC entry 243 (class 1255 OID 57602)
-- Name: check_limite_team_periodo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_limite_team_periodo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inizioReg DATE;
    v_dataInizioEvento DATE;
BEGIN
    SELECT inizioReg, dataInizio INTO v_inizioReg, v_dataInizioEvento
    FROM Evento
    WHERE idEvento = NEW.idEvento;

    IF v_inizioReg IS NULL OR v_dataInizioEvento IS NULL THEN
        RAISE EXCEPTION 'Errore: Date Evento % non definite.', NEW.idEvento;
    END IF;

    IF CURRENT_DATE < v_inizioReg THEN
        RAISE EXCEPTION 'La creazione di Team è consentita solo dopo l''inizio delle registrazioni Evento (dal %).', v_inizioReg;
    END IF;

    IF CURRENT_DATE >= v_dataInizioEvento THEN
        RAISE EXCEPTION 'Impossibile creare il Team. L''Evento % è già iniziato il %.',  NEW.idEvento, v_dataInizioEvento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_limite_team_periodo() OWNER TO postgres;

--
-- TOC entry 244 (class 1255 OID 57604)
-- Name: check_limite_upload_documento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_limite_upload_documento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_dataInizio DATE;
    v_dataFine DATE;
BEGIN
    SELECT E.dataInizio, E.dataFine INTO v_dataInizio, v_dataFine
    FROM Team T JOIN Evento E ON T.idEvento = E.idEvento
    WHERE T.idTeam = NEW.idTeam;

    IF NOT FOUND OR v_dataInizio IS NULL OR v_dataFine IS NULL THEN
         RAISE EXCEPTION 'Errore di sistema: Impossibile recuperare le date dell''evento associate al team %.', NEW.idTeam;
    END IF;

    IF CURRENT_DATE < v_dataInizio THEN
        RAISE EXCEPTION 'Il caricamento dei documenti è consentito solo a partire dall''inizio dell''evento (dal %).', v_dataInizio;
    END IF;

    IF CURRENT_DATE > v_dataFine THEN
        RAISE EXCEPTION 'Impossibile caricare documenti. L''evento è terminato il %.', v_dataFine;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_limite_upload_documento() OWNER TO postgres;

--
-- TOC entry 264 (class 1255 OID 57600)
-- Name: check_max_iscritti_evento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_max_iscritti_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_iscritti_correnti INT;
	v_max_iscritti INT;
BEGIN
	v_iscritti_correnti := conta_iscritti_evento(NEW.idEvento);

	SELECT nMaxIscritti INTO v_max_iscritti
	FROM Evento 
	WHERE idEvento = NEW.idEvento;

	IF v_iscritti_correnti >= v_max_iscritti THEN
		RAISE EXCEPTION 'Numero massimo di iscritti per l''evento raggiunto (Max: %).', v_max_iscritti;
	END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_max_iscritti_evento() OWNER TO postgres;

--
-- TOC entry 263 (class 1255 OID 57590)
-- Name: check_max_team_size(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_max_team_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_membri_correnti INT;
	v_dim_max_team INT;
BEGIN
	v_membri_correnti := conta_membri_team(NEW.idTeam);

	SELECT E.dimMaxTeam INTO v_dim_max_team
	FROM Evento E JOIN Team T ON T.idEvento = E.idEvento
	WHERE T.idTeam = NEW.idTeam;

	IF v_membri_correnti >= v_dim_max_team THEN
		RAISE EXCEPTION 'Il Team ha gia raggiunto la dimensione massima prevista dall''evento (% membri).', v_dim_max_team;
	END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_max_team_size() OWNER TO postgres;

--
-- TOC entry 294 (class 1255 OID 73747)
-- Name: check_nuovo_giudice_non_partecipante(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_nuovo_giudice_non_partecipante() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idUtenteGiudice INT;
    v_isPartecipante INT;
BEGIN
    SELECT idUtente INTO v_idUtenteGiudice
    FROM Giudice
    WHERE idGiudice = NEW.idGiudice;

    SELECT 1 INTO v_isPartecipante
    FROM Partecipazione PA
    JOIN Partecipante P ON PA.idPartecipante = P.idPartecipante
    WHERE P.idUtente = v_idUtenteGiudice
      AND PA.idEvento = NEW.idEvento 
    LIMIT 1;

    IF v_isPartecipante IS NOT NULL THEN
        RAISE EXCEPTION 'L''utente è già iscritto come Partecipante all''evento % e non può accettare l''incarico di Giudice.', NEW.idEvento;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_nuovo_giudice_non_partecipante() OWNER TO postgres;

--
-- TOC entry 239 (class 1255 OID 57582)
-- Name: check_prerequisiti_giudice(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_prerequisiti_giudice() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_data_nascita DATE;
BEGIN
	SELECT dataNascita INTO v_data_nascita
    FROM Utente
    WHERE idUtente = NEW.idUtente;

	IF NOT FOUND THEN 
		RAISE EXCEPTION 'Errore di integrità: L''ID Utente % non esiste.', NEW.idUtente;
    END IF;
	
 	IF v_data_nascita > CURRENT_DATE - INTERVAL '18 years' THEN
        RAISE EXCEPTION 'L''utente deve avere almeno 18 anni per diventare Giudice.';
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_prerequisiti_giudice() OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 57580)
-- Name: check_prerequisiti_organizzatore(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_prerequisiti_organizzatore() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_data_nascita DATE;
BEGIN
	SELECT dataNascita INTO v_data_nascita
    FROM Utente
    WHERE idUtente = NEW.idUtente;

	IF NOT FOUND THEN 
		RAISE EXCEPTION 'Errore di integrità: L''ID Utente % non esiste.', NEW.idUtente;
    END IF;
	
 	IF v_data_nascita > CURRENT_DATE - INTERVAL '18 years' THEN
        RAISE EXCEPTION 'L''utente deve avere almeno 18 anni per diventare Organizzatore.';
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_prerequisiti_organizzatore() OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 57606)
-- Name: check_problema_pubblicato_upload(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_problema_pubblicato_upload() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idEvento INT;
    v_problema_settato TEXT;
BEGIN
    SELECT idEvento INTO v_idEvento
    FROM Team
    WHERE idTeam = NEW.idTeam;

    SELECT problema INTO v_problema_settato
    FROM Evento
    WHERE idEvento = v_idEvento;

    IF v_problema_settato IS NULL THEN
        RAISE EXCEPTION 'La consegna dei documenti non è permessa finché il problema per l''Evento % non è stato ufficialmente pubblicato.', v_idEvento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_problema_pubblicato_upload() OWNER TO postgres;

--
-- TOC entry 240 (class 1255 OID 57584)
-- Name: check_setta_problema(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_setta_problema() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF CURRENT_DATE != OLD.dataInizio THEN
        RAISE EXCEPTION 'Il problema è gestibile solo il giorno di inizio evento (%). Data odierna: %.', OLD.dataInizio, CURRENT_DATE;
    END IF;

    IF NEW.problema IS NULL THEN
         RAISE EXCEPTION 'Il problema non può essere lasciato NULL.';
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_setta_problema() OWNER TO postgres;

--
-- TOC entry 268 (class 1255 OID 57616)
-- Name: check_unique_autore_problema(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_unique_autore_problema() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_conteggio_autori INT;
BEGIN
    IF NEW.ruolo = 'Autore Problema' THEN
        SELECT COUNT(*) INTO v_conteggio_autori
        FROM Giudica
        WHERE idEvento = NEW.idEvento AND ruolo = 'Autore Problema' AND idGiudice <> NEW.idGiudice;

        IF v_conteggio_autori >= 1 THEN
            RAISE EXCEPTION 'Violazione Unicità Ruolo: L''Evento % ha già un Giudice assegnato come Autore Problema.', NEW.idEvento;
        END IF;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_unique_autore_problema() OWNER TO postgres;

--
-- TOC entry 267 (class 1255 OID 57612)
-- Name: check_update_ruolo_giudice(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_update_ruolo_giudice() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_data_inizio DATE;
BEGIN
    IF NEW.ruolo IS NOT DISTINCT FROM OLD.ruolo THEN
        RETURN NEW;
    END IF;

    IF NEW.ruolo = 'Autore Problema' THEN
        SELECT dataInizio INTO v_data_inizio
        FROM Evento
        WHERE idEvento = NEW.idEvento;

        IF CURRENT_DATE >= v_data_inizio THEN
            RAISE EXCEPTION 'Il ruolo "Autore Problema" deve essere assegnato al massimo il giorno prima dell''inizio evento (%).', v_data_inizio;
        END IF;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_update_ruolo_giudice() OWNER TO postgres;

--
-- TOC entry 272 (class 1255 OID 57614)
-- Name: check_voto_post_evento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_voto_post_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_dataFineEvento DATE;
BEGIN
    SELECT E.dataFine INTO v_dataFineEvento
    FROM Team T JOIN Evento E ON T.idEvento = E.idEvento
    WHERE T.idTeam = NEW.idTeam;

    IF CURRENT_DATE <= v_dataFineEvento THEN
        RAISE EXCEPTION 'Il voto per l''Evento del Team % può essere assegnato solo DOPO la sua conclusione (%).', NEW.idTeam, v_dataFineEvento;
    END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_voto_post_evento() OWNER TO postgres;

--
-- TOC entry 282 (class 1255 OID 57630)
-- Name: commenta_documento(integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.commenta_documento(p_idgiudice integer, p_iddocumento integer, p_testocommento text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_team_associato INT;
    v_evento_documento INT;
    v_giudice_assegnato_evento BOOLEAN;
BEGIN
    SELECT D.idTeam, T.idEvento INTO v_team_associato, v_evento_documento
    FROM Documento D JOIN Team T ON D.idTeam = T.idTeam
    WHERE D.idDocumento = p_idDocumento;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Il documento con ID % non esiste o non è collegato a un team valido.', p_idDocumento;
    END IF;

    SELECT EXISTS (
        SELECT 1 
        FROM Giudica 
        WHERE idGiudice = p_idGiudice AND idEvento = v_evento_documento
    ) INTO v_giudice_assegnato_evento;
    
    IF v_giudice_assegnato_evento IS FALSE THEN
        RAISE EXCEPTION 'Il Giudice % non è autorizzato a valutare documenti dell''Evento %.', p_idGiudice, v_evento_documento;
    END IF;

    INSERT INTO Commenta (idDocumento, testo, idGiudice)
    VALUES (p_idDocumento, p_testoCommento, p_idGiudice);

    RETURN 'Commento inserito con successo sul Documento ' || p_idDocumento || ' (Evento ' || v_evento_documento || ') dal Giudice ' || p_idGiudice || '.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante l''inserimento del commento: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.commenta_documento(p_idgiudice integer, p_iddocumento integer, p_testocommento text) OWNER TO postgres;

--
-- TOC entry 257 (class 1255 OID 65556)
-- Name: conta_iscritti_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.conta_iscritti_evento(p_idevento integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_count INT;
BEGIN
	SELECT COUNT(*) INTO v_count
	FROM Partecipazione
	WHERE idEvento = p_idEvento;

	RETURN v_count;
END;
$$;


ALTER FUNCTION public.conta_iscritti_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 250 (class 1255 OID 65555)
-- Name: conta_membri_team(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.conta_membri_team(p_idteam integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_count INT;
BEGIN
	SELECT COUNT(*) INTO v_count
	FROM Appartenenza
	WHERE idTeam = p_idTeam;

	RETURN v_count;
END;
$$;


ALTER FUNCTION public.conta_membri_team(p_idteam integer) OWNER TO postgres;

--
-- TOC entry 270 (class 1255 OID 57619)
-- Name: crea_evento_e_organizzatore(integer, character varying, date, date, integer, integer, date, date, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crea_evento_e_organizzatore(p_idutente integer, p_titolo character varying, p_inizioreg date, p_finereg date, p_dimmaxteam integer, p_nmaxiscritti integer, p_datainizio date, p_datafine date, p_via character varying, p_numerocivico character varying, p_citta character varying) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idOrganizzatore INT;
BEGIN
    SELECT idOrganizzatore INTO v_idOrganizzatore
    FROM Organizzatore
    WHERE idUtente = p_idUtente;

    IF v_idOrganizzatore IS NULL THEN
        INSERT INTO Organizzatore (idUtente)
        VALUES (p_idUtente)
        RETURNING idOrganizzatore INTO v_idOrganizzatore;
    END IF;

    INSERT INTO Evento (titolo, inizioReg, fineReg, dimMaxTeam, nMaxIscritti, dataInizio, dataFine, problema, via, numeroCivico, citta, idOrganizzatore) 
	VALUES (p_titolo, p_inizioReg, p_fineReg, p_dimMaxTeam, p_nMaxIscritti, p_dataInizio, p_dataFine, NULL, p_via, p_numeroCivico, p_citta, v_idOrganizzatore);
    
    RETURN 'Evento creato con successo e utente registrato come organizzatore.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante la creazione dell''evento o la promozione a organizzatore: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.crea_evento_e_organizzatore(p_idutente integer, p_titolo character varying, p_inizioreg date, p_finereg date, p_dimmaxteam integer, p_nmaxiscritti integer, p_datainizio date, p_datafine date, p_via character varying, p_numerocivico character varying, p_citta character varying) OWNER TO postgres;

--
-- TOC entry 271 (class 1255 OID 57620)
-- Name: crea_invito_giudice(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crea_invito_giudice(p_idorganizzatore integer, p_idutenteinvitato integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_organizzatore_evento INT;
	v_utente_esiste BOOLEAN;
BEGIN
	SELECT EXISTS (SELECT 1
        		   FROM Utente
        		   WHERE idUtente = p_idUtenteInvitato) INTO v_utente_esiste;

    IF NOT v_utente_esiste THEN
        RAISE EXCEPTION 'Errore: L''ID Utente Invitato % non esiste.', p_idUtenteInvitato;
    END IF;
	
    SELECT idOrganizzatore INTO v_organizzatore_evento
    FROM Evento
    WHERE idEvento = p_idEvento;

    IF v_organizzatore_evento IS NULL THEN
        RAISE EXCEPTION 'Errore: L''evento con ID % non esiste.', p_idEvento;
    END IF;

    IF v_organizzatore_evento != p_idOrganizzatore THEN
        RAISE EXCEPTION 'Autorizzazione negata: L''organizzatore con ID % non gestisce l''evento %.', p_idOrganizzatore, p_idEvento;
    END IF;

    INSERT INTO Invito (idUtente, idEvento, idOrganizzatore, stato)
    VALUES (p_idUtenteInvitato, p_idEvento, p_idOrganizzatore, NULL);
    
    RETURN 'Invito creato con successo per l''utente ' || p_idUtenteInvitato || ' all''evento ' || p_idEvento || '.';

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Invito già esistente: L''utente è già stato invitato (o è già giudice) per questo evento.';
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Errore di integrità: L''utente invitato o l''organizzatore non sono validi.';
END;
$$;


ALTER FUNCTION public.crea_invito_giudice(p_idorganizzatore integer, p_idutenteinvitato integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 276 (class 1255 OID 57624)
-- Name: crea_team(integer, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crea_team(p_idpartecipante integer, p_idevento integer, p_nometeam character varying) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idTeamNuovo INT;
BEGIN
    INSERT INTO Team (nomeTeam, idEvento)
    VALUES (p_nomeTeam, p_idEvento)
    RETURNING idTeam INTO v_idTeamNuovo;

    INSERT INTO Appartenenza (idPartecipante, idTeam)
    VALUES (p_idPartecipante, v_idTeamNuovo);

    RETURN 'Team "' || p_nomeTeam || '" creato con successo. ID: ' || v_idTeamNuovo;

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Errore: Esiste già un team chiamato "%" per questo evento.', p_nomeTeam;
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Errore di integrità: Dati evento non validi.';
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', SQLERRM;
END;
$$;


ALTER FUNCTION public.crea_team(p_idpartecipante integer, p_idevento integer, p_nometeam character varying) OWNER TO postgres;

--
-- TOC entry 292 (class 1255 OID 65568)
-- Name: get_classifica_finale_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_classifica_finale_evento(p_idevento integer) RETURNS TABLE(titolo character varying, nometeam character varying, punteggio_medio numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
        RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
    END IF;

	RETURN QUERY
	SELECT E.titolo, T.nomeTeam, COALESCE(CAST(AVG(V.valore) AS DECIMAL(4, 2)), 0.00) AS punteggio_medio
	FROM Team T JOIN Evento E ON T.idEvento = E.idEvento LEFT JOIN Vota V ON V.idTeam = T.idTeam
	WHERE E.idEvento = p_idEvento
	GROUP BY E.titolo, T.nomeTeam
	ORDER BY punteggio_medio DESC;
	
END;
$$;


ALTER FUNCTION public.get_classifica_finale_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 286 (class 1255 OID 65565)
-- Name: get_giudici_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_giudici_evento(p_idevento integer) RETURNS TABLE(idgiudice integer, nome character varying, cognome character varying, email character varying, ruolo character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
		RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
	END IF;
	
	RETURN QUERY
	SELECT G.idGiudice, U.nome, U.cognome, U.email, GA.ruolo
	FROM Giudica GA JOIN Giudice G ON GA.idGiudice = G.idGiudice JOIN Utente U ON U.idUtente = G.idUtente
	WHERE GA.idEvento = p_idEvento;
	
END;
$$;


ALTER FUNCTION public.get_giudici_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 289 (class 1255 OID 65557)
-- Name: get_media_voti_team(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_media_voti_team(p_idteam integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_media DECIMAL(4,2);
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Team WHERE idTeam = p_idTeam) THEN
        RAISE EXCEPTION 'Errore: Il Team con ID % non esiste.', p_idTeam;
    END IF;
	
    SELECT COALESCE(AVG(valore), 0) INTO v_media
    FROM Vota
    WHERE idTeam = p_idTeam;
    
    RETURN v_media;
END;
$$;


ALTER FUNCTION public.get_media_voti_team(p_idteam integer) OWNER TO postgres;

--
-- TOC entry 242 (class 1255 OID 65564)
-- Name: get_membri_team(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_membri_team(p_idteam integer) RETURNS TABLE(nometeam character varying, idpartecipante integer, nome character varying, cognome character varying, email character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Team WHERE idTeam = p_idTeam) THEN
        RAISE EXCEPTION 'Errore: Il Team con ID % non esiste.', p_idTeam;
    END IF;
	
	RETURN QUERY
	SELECT T.nomeTeam, P.idPartecipante, U.nome, U.cognome, U.email
	FROM Appartenenza A JOIN Team T ON A.idTeam = T.idTeam JOIN Partecipante P ON A.idPartecipante = P.idPartecipante JOIN Utente U ON U.idUtente = P.idUtente
	WHERE A.idTeam = p_idTeam;
END;
$$;


ALTER FUNCTION public.get_membri_team(p_idteam integer) OWNER TO postgres;

--
-- TOC entry 287 (class 1255 OID 65567)
-- Name: get_organizzatore_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_organizzatore_evento(p_idevento integer) RETURNS TABLE(idorganizzatore integer, nome character varying, cognome character varying, email character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
		RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
	END IF;
	
	RETURN QUERY
	SELECT O.idOrganizzatore, U.nome, U.cognome, U.email
	FROM Organizzatore O JOIN Evento E ON E.idOrganizzatore = O.idOrganizzatore JOIN Utente U ON U.idUtente = O.idUtente
	WHERE E.idEvento = p_idEvento;
	
END;
$$;


ALTER FUNCTION public.get_organizzatore_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 288 (class 1255 OID 65563)
-- Name: get_partecipanti_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_partecipanti_evento(p_idevento integer) RETURNS TABLE(idpartecipante integer, nome character varying, cognome character varying, email character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
        RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
    END IF;
	
	RETURN QUERY
	SELECT PA.idPartecipante, U.nome, U.cognome, U.email
	FROM Partecipazione P JOIN Partecipante PA ON P.idPartecipante = PA.idPartecipante JOIN Utente U ON U.idUtente = PA.idUtente
	WHERE P.idEvento = p_idEvento;
END;
$$;


ALTER FUNCTION public.get_partecipanti_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 284 (class 1255 OID 57633)
-- Name: get_potenziali_giudici(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_potenziali_giudici(p_idevento integer) RETURNS TABLE(idutente integer, nome character varying, cognome character varying, username character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT U.idUtente, U.nome, U.cognome, U.username
    FROM Utente U
    WHERE U.dataNascita <= CURRENT_DATE - INTERVAL '18 years' 
        AND NOT EXISTS (SELECT 1
            			FROM Giudice G JOIN Giudica J ON G.idGiudice = J.idGiudice
            			WHERE G.idUtente = U.idUtente AND J.idEvento = p_idEvento)
        AND NOT EXISTS (SELECT 1
            			FROM Partecipante P JOIN Partecipazione PA ON P.idPartecipante = PA.idPartecipante
            			WHERE P.idUtente = U.idUtente AND PA.idEvento = p_idEvento)
        AND U.idUtente NOT IN (SELECT O.idUtente
            				   FROM Organizzatore O JOIN Evento E ON O.idOrganizzatore = E.idOrganizzatore
            				   WHERE E.idEvento = p_idEvento)
        AND NOT EXISTS (SELECT 1
            			FROM Invito I
            			WHERE I.idUtente = U.idUtente AND I.idEvento = p_idEvento AND I.stato = 'Rifiutato');
END;
$$;


ALTER FUNCTION public.get_potenziali_giudici(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 65571)
-- Name: get_storico_utente(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_storico_utente(p_idutente integer) RETURNS TABLE(nome character varying, cognome character varying, username character varying, titolo character varying, datainizio date, datafine date, nometeam character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_idPartecipante INT;
BEGIN
	IF NOT EXISTS (SELECT 1 FROM Utente WHERE idUtente = p_idUtente) THEN
        RAISE EXCEPTION 'Errore: L''Utente con ID % non esiste nel sistema.', p_idUtente;
    END IF;
	
	SELECT idPartecipante INTO v_idPartecipante
    FROM Partecipante
    WHERE idUtente = p_idUtente;

    IF v_idPartecipante IS NULL THEN
        RAISE EXCEPTION 'L''utente non è mai stato partecipante.';
    END IF;

	RETURN QUERY
	SELECT U.nome, U.cognome, U.username, E.titolo, E.dataInizio, E.dataFine, T.nomeTeam
	FROM Appartenenza A JOIN Team T ON A.idTeam = T.idTeam JOIN Partecipante P ON A.idPartecipante = P.idPartecipante 
	JOIN Evento E ON T.idEvento = E.idEvento JOIN Utente U ON U.idUtente = P.idUtente
	WHERE A.idPartecipante = v_idPartecipante
	ORDER BY E.dataInizio DESC;

END;
$$;


ALTER FUNCTION public.get_storico_utente(p_idutente integer) OWNER TO postgres;

--
-- TOC entry 290 (class 1255 OID 65569)
-- Name: get_team_disponibili_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_team_disponibili_evento(p_idevento integer) RETURNS TABLE(idteam integer, nometeam character varying, membri_attuali integer, posti_totali integer, posti_rimanenti integer)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
		RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
	END IF;

	RETURN QUERY
	SELECT T.idTeam, T.nomeTeam, conta_membri_team(T.idTeam) AS membri_attuali, E.dimMaxTeam AS posti_totali, (E.dimMaxTeam - conta_membri_team(T.idTeam)) AS posti_rimanenti
	FROM Team T JOIN Evento E ON E.idEvento = T.idEvento
	WHERE T.idEvento = p_idEvento AND conta_membri_team(T.idTeam) < E.dimMaxTeam
	ORDER BY posti_rimanenti DESC;
	
END;
$$;


ALTER FUNCTION public.get_team_disponibili_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 65570)
-- Name: get_team_evento(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_team_evento(p_idevento integer) RETURNS TABLE(idteam integer, nometeam character varying, numero_membri integer)
    LANGUAGE plpgsql
    AS $$
BEGIN

	IF NOT EXISTS (SELECT 1 FROM Evento WHERE idEvento = p_idEvento) THEN
		RAISE EXCEPTION 'Errore: L''Evento con ID % non esiste.', p_idEvento;
	END IF;

	RETURN QUERY
	SELECT T.idTeam, T.nomeTeam, conta_membri_team(T.idTeam) AS numero_membri
	FROM Team T
	WHERE T.idEvento = p_idEvento;
	
END;
$$;


ALTER FUNCTION public.get_team_evento(p_idevento integer) OWNER TO postgres;

--
-- TOC entry 277 (class 1255 OID 57625)
-- Name: iscrivi_team(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.iscrivi_team(p_idpartecipante integer, p_idteam integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_eventoId INT;
BEGIN
    SELECT idEvento INTO v_eventoId
    FROM Team
    WHERE idTeam = p_idTeam;

    IF v_eventoId IS NULL THEN
        RAISE EXCEPTION 'Errore: Il Team ID % non esiste.', p_idTeam;
    END IF;

    IF v_eventoId <> p_idEvento THEN
        RAISE EXCEPTION 'Errore: Il Team % non appartiene all''Evento specificato (ID %).', p_idTeam, p_idEvento;
    END IF;

    INSERT INTO Appartenenza (idPartecipante, idTeam)
    VALUES (p_idPartecipante, p_idTeam);

    RETURN 'Partecipante ' || p_idPartecipante || ' iscritto con successo al Team ' || p_idTeam || '.';

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Il partecipante è già membro di questo team.';
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Errore di integrità: ID Partecipante o Team non validi.';
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', SQLERRM;
END;
$$;


ALTER FUNCTION public.iscrivi_team(p_idpartecipante integer, p_idteam integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 275 (class 1255 OID 57623)
-- Name: iscrivi_utente_evento(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.iscrivi_utente_evento(p_idutente integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idPartecipanteFinale INT;
BEGIN
    IF NOT EXISTS (SELECT 1 
					FROM Evento 
					WHERE idEvento = p_idEvento) THEN
        RAISE EXCEPTION 'Errore: L''evento con ID % non esiste.', p_idEvento;
    END IF;

   	SELECT idPartecipante INTO v_idPartecipanteFinale
    FROM Partecipante
    WHERE idUtente = p_idUtente;

	IF v_idPartecipanteFinale IS NULL THEN
    	INSERT INTO Partecipante (idUtente)
    	VALUES (p_idUtente)
    	RETURNING idPartecipante INTO v_idPartecipanteFinale;
    END IF;
	
    INSERT INTO Partecipazione (idPartecipante, idEvento, dataIscrizione)
    VALUES (v_idPartecipanteFinale, p_idEvento, CURRENT_DATE);

    RETURN 'Iscrizione completata con successo per l''evento ' || p_idEvento || '.';
	
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Attenzione: L''utente con ID % è già iscritto a questo evento.', p_idUtente;
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Errore di integrità: Impossibile iscrivere. Dati non validi.';
END;
$$;


ALTER FUNCTION public.iscrivi_utente_evento(p_idutente integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 269 (class 1255 OID 57618)
-- Name: registra_utente(character varying, character varying, character varying, character varying, character varying, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registra_utente(p_nome character varying, p_cognome character varying, p_email character varying, p_username character varying, p_password character varying, p_datanascita date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nuovoIdUtente INT;
BEGIN
    INSERT INTO Utente (nome, cognome, email, username, password, dataNascita) 
    VALUES (p_nome, p_cognome, p_email, p_username, p_password, p_dataNascita)
    RETURNING idUtente INTO v_nuovoIdUtente;

    RETURN v_nuovoIdUtente;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Registrazione fallita: L''email o l''username forniti sono già in uso da un altro account.';
    WHEN not_null_violation THEN
        RAISE EXCEPTION 'Errore: Mancano dati obbligatori per la registrazione.';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante la registrazione: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.registra_utente(p_nome character varying, p_cognome character varying, p_email character varying, p_username character varying, p_password character varying, p_datanascita date) OWNER TO postgres;

--
-- TOC entry 274 (class 1255 OID 57622)
-- Name: rifiuta_invito_giudice(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rifiuta_invito_giudice(p_idutente integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_stato_attuale VARCHAR;
BEGIN
    SELECT stato INTO v_stato_attuale
    FROM Invito
    WHERE idUtente = p_idUtente AND idEvento = p_idEvento;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Nessun invito trovato per l''utente % all''evento %.', p_idUtente, p_idEvento;
    END IF;

    IF v_stato_attuale IS NULL THEN
        UPDATE Invito
        SET stato = 'Rifiutato'
        WHERE idUtente = p_idUtente AND idEvento = p_idEvento; 
        
        RETURN 'Invito rifiutato con successo.';

    ELSIF v_stato_attuale = 'Rifiutato' THEN
        RAISE EXCEPTION 'L''utente ha già rifiutato l''invito.';
    ELSIF v_stato_attuale = 'Accettato' THEN
        RAISE EXCEPTION 'Impossibile rifiutare: l''invito è già stato accettato.';
    ELSE
        RAISE EXCEPTION 'Stato invito sconosciuto: %', v_stato_attuale;
    END IF;
END;
$$;


ALTER FUNCTION public.rifiuta_invito_giudice(p_idutente integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 280 (class 1255 OID 57628)
-- Name: setta_problema_evento(integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.setta_problema_evento(p_idgiudice integer, p_idevento integer, p_nuovoproblema text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ruolo_giudice VARCHAR;
BEGIN
    SELECT G.ruolo INTO v_ruolo_giudice
    FROM Giudica G
    WHERE G.idGiudice = p_idGiudice AND G.idEvento = p_idEvento;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Giudice % non assegnato all''Evento %.', p_idGiudice, p_idEvento;
    END IF;

    IF v_ruolo_giudice != 'Autore Problema' THEN
        RAISE EXCEPTION 'Il Giudice % (Ruolo: %) non ha il permesso di settare il problema.', p_idGiudice, v_ruolo_giudice;
    END IF;

    UPDATE Evento
    SET problema = p_nuovoProblema
    WHERE idEvento = p_idEvento;

    RETURN 'Problema settato con successo per l''Evento ' || p_idEvento || ' dall''Autore Problema (ID: ' || p_idGiudice || ').';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante l''impostazione del problema: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.setta_problema_evento(p_idgiudice integer, p_idevento integer, p_nuovoproblema text) OWNER TO postgres;

--
-- TOC entry 279 (class 1255 OID 57627)
-- Name: setta_ruolo_autore_problema(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.setta_ruolo_autore_problema(p_idorganizzatore integer, p_idgiudice integer, p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_idOrganizzatoreEvento INT;
    v_data_inizio DATE;
BEGIN
    SELECT idOrganizzatore, dataInizio INTO v_idOrganizzatoreEvento, v_data_inizio
    FROM Evento
    WHERE idEvento = p_idEvento;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Evento con ID % non trovato.', p_idEvento;
    END IF;

    IF v_idOrganizzatoreEvento != p_idOrganizzatore THEN 
        RAISE EXCEPTION 'Accesso negato: L''Organizzatore % non è l''organizzatore responsabile dell''Evento %.', p_idOrganizzatore, p_idEvento;
    END IF;

    UPDATE Giudica
    SET ruolo = 'Autore Problema' 
    WHERE idGiudice = p_idGiudice AND idEvento = p_idEvento;
 
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Errore: Il Giudice % non è assegnato all''Evento % .', p_idGiudice, p_idEvento;
    END IF;
 
    RETURN 'Ruolo "Autore Problema" assegnato con successo al Giudice ' || p_idGiudice || ' per l''Evento ' || p_idEvento || ' (Deadline: ' || v_data_inizio || ')';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Errore durante l''assegnazione del ruolo: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.setta_ruolo_autore_problema(p_idorganizzatore integer, p_idgiudice integer, p_idevento integer) OWNER TO postgres;

--
-- TOC entry 278 (class 1255 OID 57626)
-- Name: team_con_autoassegnazione(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.team_con_autoassegnazione(p_idevento integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_dataInizioEvento DATE;
    v_partecipante_record RECORD;
    v_idTeamNuovo INT;
    v_conteggio_assegnazioni INT := 0;
    v_team_name VARCHAR;
BEGIN
    SELECT dataInizio INTO v_dataInizioEvento
    FROM Evento
    WHERE idEvento = p_idEvento;

    IF v_dataInizioEvento IS NULL THEN
        RAISE EXCEPTION 'Errore: Data di inizio evento non definita per ID %. ', p_idEvento;
    END IF;

    IF CURRENT_DATE >= v_dataInizioEvento THEN
        RAISE EXCEPTION 'Impossibile assegnare team automaticamente. L''Evento % e gia iniziato (Inizio: %).', p_idEvento, v_dataInizioEvento;
    END IF;

    FOR v_partecipante_record IN (SELECT P.idPartecipante, U.username 
								   FROM Partecipazione PA JOIN Partecipante P ON PA.idPartecipante = P.idPartecipante
            					   JOIN Utente U ON P.idUtente = U.idUtente
            					   WHERE PA.idEvento = p_idEvento AND NOT EXISTS (SELECT 1
                																   FROM Appartenenza A JOIN Team T ON A.idTeam = T.idTeam
                																   WHERE A.idPartecipante = P.idPartecipante AND T.idEvento = p_idEvento
																				   )
        						  )
    LOOP
        v_team_name := 'Team Autogestito - ' || v_partecipante_record.username;

        INSERT INTO Team (nomeTeam, idEvento)
        VALUES (v_team_name, p_idEvento)
        RETURNING idTeam INTO v_idTeamNuovo;

        INSERT INTO Appartenenza (idPartecipante, idTeam)
        VALUES (v_partecipante_record.idPartecipante, v_idTeamNuovo);

        v_conteggio_assegnazioni := v_conteggio_assegnazioni + 1;
    END LOOP;

    IF v_conteggio_assegnazioni > 0 THEN
        RETURN 'Sono stati creati ' || v_conteggio_assegnazioni || ' team mono-membro per i partecipanti orfani dell''Evento ' || p_idEvento || '.';
    ELSE
        RETURN 'Nessun partecipante orfano trovato per l''Evento ' || p_idEvento || '. Tutti sono già in un team.';
    END IF;
END;
$$;


ALTER FUNCTION public.team_con_autoassegnazione(p_idevento integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 236 (class 1259 OID 57563)
-- Name: appartenenza; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.appartenenza (
    idpartecipante integer NOT NULL,
    idteam integer NOT NULL
);


ALTER TABLE public.appartenenza OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 57530)
-- Name: commenta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.commenta (
    idgiudice integer NOT NULL,
    iddocumento integer NOT NULL,
    testo text NOT NULL,
    CONSTRAINT chk_testo CHECK ((TRIM(BOTH FROM testo) <> ''::text))
);


ALTER TABLE public.commenta OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 57513)
-- Name: documento_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.documento_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.documento_id OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 57514)
-- Name: documento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.documento (
    iddocumento integer DEFAULT nextval('public.documento_id'::regclass) NOT NULL,
    pathdoc text NOT NULL,
    datadoc timestamp without time zone NOT NULL,
    idteam integer NOT NULL,
    CONSTRAINT chk_pathdocumento CHECK (((TRIM(BOTH FROM pathdoc) <> ''::text) AND (pathdoc ~ '^\/?([^/\0]+/?)*[^/\0]+\.(pdf|docx?|docm|txt|pages|odt|rtf|tex)$'::text)))
);


ALTER TABLE public.documento OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 57418)
-- Name: evento_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.evento_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evento_id OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 57419)
-- Name: evento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.evento (
    idevento integer DEFAULT nextval('public.evento_id'::regclass) NOT NULL,
    titolo character varying(100) NOT NULL,
    inizioreg date NOT NULL,
    finereg date NOT NULL,
    dimmaxteam integer NOT NULL,
    nmaxiscritti integer NOT NULL,
    datainizio date NOT NULL,
    datafine date NOT NULL,
    problema text,
    via character varying(50) NOT NULL,
    numerocivico character varying(10) NOT NULL,
    citta character varying(50) NOT NULL,
    idorganizzatore integer NOT NULL,
    CONSTRAINT chk_dimmaxteam CHECK ((dimmaxteam > 0)),
    CONSTRAINT chk_nmaxiscritti CHECK ((nmaxiscritti > 0)),
    CONSTRAINT chk_problemacompleto CHECK (((TRIM(BOTH FROM problema) <> ''::text) AND (length(TRIM(BOTH FROM problema)) >= 10))),
    CONSTRAINT chk_sequenzaevento CHECK ((datainizio < datafine)),
    CONSTRAINT chk_sequenzaregistrazione CHECK ((inizioreg < finereg)),
    CONSTRAINT chk_tempistichehackathon CHECK (((datainizio - finereg) = 2)),
    CONSTRAINT chk_titoloevento CHECK ((TRIM(BOTH FROM titolo) <> ''::text)),
    CONSTRAINT chk_validitacitta CHECK (((citta)::text ~* '^[a-zA-Z\àèéìòùÀÈÉÌÒÙ''\s]+$'::text)),
    CONSTRAINT chk_validitanumerocivico CHECK (((numerocivico)::text ~ '^[a-zA-Z0-9]+$'::text)),
    CONSTRAINT chk_validitavia CHECK (((via)::text ~* '^[a-zA-Z\àèéìòùÀÈÉÌÒÙ''\s]+$'::text))
);


ALTER TABLE public.evento OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 57444)
-- Name: giudica; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.giudica (
    idgiudice integer NOT NULL,
    idevento integer NOT NULL,
    ruolo character varying(20) DEFAULT 'Giudice Standard'::character varying,
    CONSTRAINT chk_ruologiudice CHECK (((ruolo)::text = ANY ((ARRAY['Giudice Standard'::character varying, 'Autore Problema'::character varying])::text[])))
);


ALTER TABLE public.giudica OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 57394)
-- Name: giudice_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.giudice_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.giudice_id OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 57395)
-- Name: giudice; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.giudice (
    idgiudice integer DEFAULT nextval('public.giudice_id'::regclass) NOT NULL,
    idutente integer NOT NULL
);


ALTER TABLE public.giudice OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 57461)
-- Name: invito; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.invito (
    stato character varying(10),
    idutente integer NOT NULL,
    idevento integer NOT NULL,
    idorganizzatore integer NOT NULL,
    CONSTRAINT chk_statoinvito CHECK (((stato IS NULL) OR ((stato)::text = ANY ((ARRAY['Accettato'::character varying, 'Rifiutato'::character varying])::text[]))))
);


ALTER TABLE public.invito OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 57382)
-- Name: organizzatore_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.organizzatore_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.organizzatore_id OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 57383)
-- Name: organizzatore; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organizzatore (
    idorganizzatore integer DEFAULT nextval('public.organizzatore_id'::regclass) NOT NULL,
    idutente integer NOT NULL
);


ALTER TABLE public.organizzatore OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 57406)
-- Name: partecipante_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partecipante_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partecipante_id OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 57407)
-- Name: partecipante; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partecipante (
    idpartecipante integer DEFAULT nextval('public.partecipante_id'::regclass) NOT NULL,
    idutente integer NOT NULL
);


ALTER TABLE public.partecipante OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 57548)
-- Name: partecipazione; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partecipazione (
    idpartecipante integer NOT NULL,
    idevento integer NOT NULL,
    dataiscrizione date NOT NULL
);


ALTER TABLE public.partecipazione OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 57482)
-- Name: team_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.team_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_id OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 57483)
-- Name: team; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.team (
    idteam integer DEFAULT nextval('public.team_id'::regclass) NOT NULL,
    nometeam character varying(50) NOT NULL,
    idevento integer NOT NULL,
    CONSTRAINT chk_nometeam CHECK ((TRIM(BOTH FROM nometeam) <> ''::text))
);


ALTER TABLE public.team OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 57367)
-- Name: utente_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.utente_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.utente_id OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 57368)
-- Name: utente; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.utente (
    idutente integer DEFAULT nextval('public.utente_id'::regclass) NOT NULL,
    nome character varying(30) NOT NULL,
    cognome character varying(30) NOT NULL,
    datanascita date NOT NULL,
    email character varying(100) NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(30) NOT NULL,
    CONSTRAINT chk_cognome CHECK (((cognome)::text ~ '^[a-zA-Z\s]+$'::text)),
    CONSTRAINT chk_email CHECK (((email)::text ~* '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9+-]+\.[a-zA-Z]{2,4}$'::text)),
    CONSTRAINT chk_nome CHECK (((nome)::text ~ '^[a-zA-Z\s]+$'::text)),
    CONSTRAINT chk_password CHECK (((password)::text ~* '^(?=.*[A-Z])(?=.*[0-9])(?=.*[^a-zA-Z0-9\s]).{8,}$'::text))
);


ALTER TABLE public.utente OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 57497)
-- Name: vota; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vota (
    valore integer NOT NULL,
    idteam integer NOT NULL,
    idgiudice integer NOT NULL,
    CONSTRAINT chk_valore CHECK (((valore >= 0) AND (valore <= 10)))
);


ALTER TABLE public.vota OWNER TO postgres;

--
-- TOC entry 4906 (class 2606 OID 57567)
-- Name: appartenenza appartenenza_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.appartenenza
    ADD CONSTRAINT appartenenza_pkey PRIMARY KEY (idpartecipante, idteam);


--
-- TOC entry 4902 (class 2606 OID 57537)
-- Name: commenta commenta_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commenta
    ADD CONSTRAINT commenta_pkey PRIMARY KEY (idgiudice, iddocumento);


--
-- TOC entry 4898 (class 2606 OID 57524)
-- Name: documento documento_pathdoc_idteam_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_pathdoc_idteam_key UNIQUE (pathdoc, idteam);


--
-- TOC entry 4900 (class 2606 OID 57522)
-- Name: documento documento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_pkey PRIMARY KEY (iddocumento);


--
-- TOC entry 4884 (class 2606 OID 57436)
-- Name: evento evento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento
    ADD CONSTRAINT evento_pkey PRIMARY KEY (idevento);


--
-- TOC entry 4886 (class 2606 OID 57438)
-- Name: evento evento_titolo_datainizio_citta_numerocivico_via_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento
    ADD CONSTRAINT evento_titolo_datainizio_citta_numerocivico_via_key UNIQUE (titolo, datainizio, citta, numerocivico, via);


--
-- TOC entry 4888 (class 2606 OID 57450)
-- Name: giudica giudica_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.giudica
    ADD CONSTRAINT giudica_pkey PRIMARY KEY (idgiudice, idevento);


--
-- TOC entry 4880 (class 2606 OID 57400)
-- Name: giudice giudice_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.giudice
    ADD CONSTRAINT giudice_pkey PRIMARY KEY (idgiudice);


--
-- TOC entry 4890 (class 2606 OID 57466)
-- Name: invito invito_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invito
    ADD CONSTRAINT invito_pkey PRIMARY KEY (idutente, idevento, idorganizzatore);


--
-- TOC entry 4878 (class 2606 OID 57388)
-- Name: organizzatore organizzatore_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizzatore
    ADD CONSTRAINT organizzatore_pkey PRIMARY KEY (idorganizzatore);


--
-- TOC entry 4882 (class 2606 OID 57412)
-- Name: partecipante partecipante_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partecipante
    ADD CONSTRAINT partecipante_pkey PRIMARY KEY (idpartecipante);


--
-- TOC entry 4904 (class 2606 OID 57552)
-- Name: partecipazione partecipazione_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partecipazione
    ADD CONSTRAINT partecipazione_pkey PRIMARY KEY (idpartecipante, idevento);


--
-- TOC entry 4892 (class 2606 OID 57491)
-- Name: team team_nometeam_idevento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_nometeam_idevento_key UNIQUE (nometeam, idevento);


--
-- TOC entry 4894 (class 2606 OID 57489)
-- Name: team team_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_pkey PRIMARY KEY (idteam);


--
-- TOC entry 4872 (class 2606 OID 57379)
-- Name: utente utente_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.utente
    ADD CONSTRAINT utente_email_key UNIQUE (email);


--
-- TOC entry 4874 (class 2606 OID 57377)
-- Name: utente utente_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.utente
    ADD CONSTRAINT utente_pkey PRIMARY KEY (idutente);


--
-- TOC entry 4876 (class 2606 OID 57381)
-- Name: utente utente_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.utente
    ADD CONSTRAINT utente_username_key UNIQUE (username);


--
-- TOC entry 4896 (class 2606 OID 57502)
-- Name: vota vota_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vota
    ADD CONSTRAINT vota_pkey PRIMARY KEY (idteam, idgiudice);


--
-- TOC entry 4945 (class 2620 OID 57589)
-- Name: appartenenza enforce_assegnazione_team; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_assegnazione_team BEFORE INSERT ON public.appartenenza FOR EACH ROW EXECUTE FUNCTION public.check_assegnazione_team();


--
-- TOC entry 4941 (class 2620 OID 57609)
-- Name: commenta enforce_commento_periodo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_commento_periodo BEFORE INSERT ON public.commenta FOR EACH ROW EXECUTE FUNCTION public.check_commento_periodo();


--
-- TOC entry 4926 (class 2620 OID 57579)
-- Name: utente enforce_eta_minima_utente; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_eta_minima_utente BEFORE INSERT OR UPDATE OF datanascita ON public.utente FOR EACH ROW EXECUTE FUNCTION public.check_eta_minima_utente();


--
-- TOC entry 4929 (class 2620 OID 57587)
-- Name: evento enforce_evento_futuro_dinamico; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_evento_futuro_dinamico BEFORE INSERT OR UPDATE OF inizioreg, datainizio ON public.evento FOR EACH ROW EXECUTE FUNCTION public.check_evento_futuro_dinamico();


--
-- TOC entry 4931 (class 2620 OID 57611)
-- Name: giudica enforce_invito_giudica; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_invito_giudica BEFORE INSERT ON public.giudica FOR EACH ROW EXECUTE FUNCTION public.check_invito_giudica();


--
-- TOC entry 4935 (class 2620 OID 57595)
-- Name: invito enforce_invito_precondizioni; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_invito_precondizioni BEFORE INSERT ON public.invito FOR EACH ROW EXECUTE FUNCTION public.check_invito_precondizioni();


--
-- TOC entry 4936 (class 2620 OID 57593)
-- Name: invito enforce_invito_prima_inizio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_invito_prima_inizio BEFORE INSERT ON public.invito FOR EACH ROW EXECUTE FUNCTION public.check_invito_prima_inizio();


--
-- TOC entry 4942 (class 2620 OID 57597)
-- Name: partecipazione enforce_iscrizione_apertura; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_iscrizione_apertura BEFORE INSERT ON public.partecipazione FOR EACH ROW EXECUTE FUNCTION public.check_iscrizione_apertura();


--
-- TOC entry 4943 (class 2620 OID 57599)
-- Name: partecipazione enforce_iscrizione_ruoli; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_iscrizione_ruoli BEFORE INSERT ON public.partecipazione FOR EACH ROW EXECUTE FUNCTION public.check_iscrizione_ruoli();


--
-- TOC entry 4937 (class 2620 OID 57603)
-- Name: team enforce_limite_team_periodo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_limite_team_periodo BEFORE INSERT ON public.team FOR EACH ROW EXECUTE FUNCTION public.check_limite_team_periodo();


--
-- TOC entry 4939 (class 2620 OID 57605)
-- Name: documento enforce_limite_upload_documento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_limite_upload_documento BEFORE INSERT ON public.documento FOR EACH ROW EXECUTE FUNCTION public.check_limite_upload_documento();


--
-- TOC entry 4944 (class 2620 OID 57601)
-- Name: partecipazione enforce_max_iscritti_evento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_max_iscritti_evento BEFORE INSERT ON public.partecipazione FOR EACH ROW EXECUTE FUNCTION public.check_max_iscritti_evento();


--
-- TOC entry 4946 (class 2620 OID 57591)
-- Name: appartenenza enforce_max_team_size; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_max_team_size BEFORE INSERT ON public.appartenenza FOR EACH ROW EXECUTE FUNCTION public.check_max_team_size();


--
-- TOC entry 4932 (class 2620 OID 73748)
-- Name: giudica enforce_nuovo_giudice_non_partecipante; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_nuovo_giudice_non_partecipante BEFORE INSERT ON public.giudica FOR EACH ROW EXECUTE FUNCTION public.check_nuovo_giudice_non_partecipante();


--
-- TOC entry 4928 (class 2620 OID 57583)
-- Name: giudice enforce_prerequisiti_giudice; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_prerequisiti_giudice BEFORE INSERT ON public.giudice FOR EACH ROW EXECUTE FUNCTION public.check_prerequisiti_giudice();


--
-- TOC entry 4927 (class 2620 OID 57581)
-- Name: organizzatore enforce_prerequisiti_organizzatore; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_prerequisiti_organizzatore BEFORE INSERT ON public.organizzatore FOR EACH ROW EXECUTE FUNCTION public.check_prerequisiti_organizzatore();


--
-- TOC entry 4940 (class 2620 OID 57607)
-- Name: documento enforce_problema_pubblicato_upload; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_problema_pubblicato_upload BEFORE INSERT ON public.documento FOR EACH ROW EXECUTE FUNCTION public.check_problema_pubblicato_upload();


--
-- TOC entry 4930 (class 2620 OID 57585)
-- Name: evento enforce_setta_problema; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_setta_problema BEFORE UPDATE OF problema ON public.evento FOR EACH ROW EXECUTE FUNCTION public.check_setta_problema();


--
-- TOC entry 4933 (class 2620 OID 57617)
-- Name: giudica enforce_unique_autore_problema; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_unique_autore_problema BEFORE INSERT OR UPDATE OF ruolo ON public.giudica FOR EACH ROW EXECUTE FUNCTION public.check_unique_autore_problema();


--
-- TOC entry 4934 (class 2620 OID 57613)
-- Name: giudica enforce_update_ruolo_giudice; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_update_ruolo_giudice BEFORE UPDATE OF ruolo ON public.giudica FOR EACH ROW EXECUTE FUNCTION public.check_update_ruolo_giudice();


--
-- TOC entry 4938 (class 2620 OID 57615)
-- Name: vota enforce_voto_post_evento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enforce_voto_post_evento BEFORE INSERT OR UPDATE OF valore ON public.vota FOR EACH ROW EXECUTE FUNCTION public.check_voto_post_evento();


--
-- TOC entry 4924 (class 2606 OID 57573)
-- Name: appartenenza appartenenza_idpartecipante_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.appartenenza
    ADD CONSTRAINT appartenenza_idpartecipante_fkey FOREIGN KEY (idpartecipante) REFERENCES public.partecipante(idpartecipante) ON DELETE CASCADE;


--
-- TOC entry 4925 (class 2606 OID 57568)
-- Name: appartenenza appartenenza_idteam_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.appartenenza
    ADD CONSTRAINT appartenenza_idteam_fkey FOREIGN KEY (idteam) REFERENCES public.team(idteam) ON DELETE CASCADE;


--
-- TOC entry 4920 (class 2606 OID 57538)
-- Name: commenta commenta_iddocumento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commenta
    ADD CONSTRAINT commenta_iddocumento_fkey FOREIGN KEY (iddocumento) REFERENCES public.documento(iddocumento) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4921 (class 2606 OID 57543)
-- Name: commenta commenta_idgiudice_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.commenta
    ADD CONSTRAINT commenta_idgiudice_fkey FOREIGN KEY (idgiudice) REFERENCES public.giudice(idgiudice) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4919 (class 2606 OID 57525)
-- Name: documento documento_idteam_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_idteam_fkey FOREIGN KEY (idteam) REFERENCES public.team(idteam) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4910 (class 2606 OID 57439)
-- Name: evento evento_idorganizzatore_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento
    ADD CONSTRAINT evento_idorganizzatore_fkey FOREIGN KEY (idorganizzatore) REFERENCES public.organizzatore(idorganizzatore) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4911 (class 2606 OID 57451)
-- Name: giudica giudica_idevento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.giudica
    ADD CONSTRAINT giudica_idevento_fkey FOREIGN KEY (idevento) REFERENCES public.evento(idevento) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4912 (class 2606 OID 57456)
-- Name: giudica giudica_idgiudice_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.giudica
    ADD CONSTRAINT giudica_idgiudice_fkey FOREIGN KEY (idgiudice) REFERENCES public.giudice(idgiudice) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4908 (class 2606 OID 57401)
-- Name: giudice giudice_idutente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.giudice
    ADD CONSTRAINT giudice_idutente_fkey FOREIGN KEY (idutente) REFERENCES public.utente(idutente) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4913 (class 2606 OID 57467)
-- Name: invito invito_idevento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invito
    ADD CONSTRAINT invito_idevento_fkey FOREIGN KEY (idevento) REFERENCES public.evento(idevento) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4914 (class 2606 OID 57472)
-- Name: invito invito_idorganizzatore_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invito
    ADD CONSTRAINT invito_idorganizzatore_fkey FOREIGN KEY (idorganizzatore) REFERENCES public.organizzatore(idorganizzatore) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4915 (class 2606 OID 57477)
-- Name: invito invito_idutente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invito
    ADD CONSTRAINT invito_idutente_fkey FOREIGN KEY (idutente) REFERENCES public.utente(idutente) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4907 (class 2606 OID 57389)
-- Name: organizzatore organizzatore_idutente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organizzatore
    ADD CONSTRAINT organizzatore_idutente_fkey FOREIGN KEY (idutente) REFERENCES public.utente(idutente) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4909 (class 2606 OID 57413)
-- Name: partecipante partecipante_idutente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partecipante
    ADD CONSTRAINT partecipante_idutente_fkey FOREIGN KEY (idutente) REFERENCES public.utente(idutente) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4922 (class 2606 OID 57553)
-- Name: partecipazione partecipazione_idevento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partecipazione
    ADD CONSTRAINT partecipazione_idevento_fkey FOREIGN KEY (idevento) REFERENCES public.evento(idevento) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4923 (class 2606 OID 57558)
-- Name: partecipazione partecipazione_idpartecipante_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partecipazione
    ADD CONSTRAINT partecipazione_idpartecipante_fkey FOREIGN KEY (idpartecipante) REFERENCES public.partecipante(idpartecipante) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4916 (class 2606 OID 57492)
-- Name: team team_idevento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.team
    ADD CONSTRAINT team_idevento_fkey FOREIGN KEY (idevento) REFERENCES public.evento(idevento) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4917 (class 2606 OID 57503)
-- Name: vota vota_idgiudice_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vota
    ADD CONSTRAINT vota_idgiudice_fkey FOREIGN KEY (idgiudice) REFERENCES public.giudice(idgiudice) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4918 (class 2606 OID 57508)
-- Name: vota vota_idteam_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vota
    ADD CONSTRAINT vota_idteam_fkey FOREIGN KEY (idteam) REFERENCES public.team(idteam) ON UPDATE CASCADE ON DELETE CASCADE;


-- Completed on 2025-11-24 12:58:12

--
-- PostgreSQL database dump complete
--

