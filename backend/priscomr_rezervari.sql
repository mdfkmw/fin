-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- Host: db:3306
-- Generation Time: Oct 30, 2025 at 09:39 PM
-- Server version: 10.11.13-MariaDB-ubu2204
-- PHP Version: 8.3.26

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `priscomr_rezervari`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`priscomr_rezervariuser`@`%` PROCEDURE `sp_fill_trip_stations` (IN `p_trip_id` INT)   proc: BEGIN
  DECLARE v_route_id INT DEFAULT NULL;
  DECLARE v_direction ENUM('tur','retur') DEFAULT 'tur';

  SELECT t.route_id, COALESCE(rs.direction, 'tur')
    INTO v_route_id, v_direction
  FROM trips t
  LEFT JOIN route_schedules rs ON rs.id = t.route_schedule_id
  WHERE t.id = p_trip_id
  LIMIT 1;

  IF v_route_id IS NULL THEN
    LEAVE proc;
  END IF;

  DELETE FROM trip_stations WHERE trip_id = p_trip_id;

  IF v_direction = 'retur' THEN
    INSERT INTO trip_stations (trip_id, station_id, sequence)
    SELECT p_trip_id, station_id, seq
    FROM (
      SELECT rs.station_id,
             ROW_NUMBER() OVER (ORDER BY rs.sequence DESC) AS seq
      FROM route_stations rs
      WHERE rs.route_id = v_route_id
    ) AS ordered;
  ELSE
    INSERT INTO trip_stations (trip_id, station_id, sequence)
    SELECT p_trip_id, rs.station_id, rs.sequence
    FROM route_stations rs
    WHERE rs.route_id = v_route_id
    ORDER BY rs.sequence;
  END IF;
END$$

CREATE DEFINER=`priscomr_rezervariuser`@`%` PROCEDURE `sp_free_seats` (IN `p_trip_id` INT, IN `p_board_station_id` INT, IN `p_exit_station_id` INT)   BEGIN
  DECLARE v_bseq INT;
  DECLARE v_eseq INT;

  SELECT sequence INTO v_bseq
  FROM trip_stations
  WHERE trip_id = p_trip_id AND station_id = p_board_station_id
  LIMIT 1;

  SELECT sequence INTO v_eseq
  FROM trip_stations
  WHERE trip_id = p_trip_id AND station_id = p_exit_station_id
  LIMIT 1;

  IF v_bseq IS NULL OR v_eseq IS NULL OR v_bseq >= v_eseq THEN
    SELECT NULL AS id, NULL AS label, NULL AS status WHERE 1=0;
  ELSE
    WITH RECURSIVE segment_bounds AS (
      SELECT v_bseq AS seq
      UNION ALL
      SELECT seq + 1 FROM segment_bounds WHERE seq + 1 < v_eseq
    ),
    seat_segments AS (
      SELECT
        s.id AS seat_id,
        sb.seq,
        MAX(
          CASE
            WHEN ts_b.sequence IS NOT NULL
             AND ts_e.sequence IS NOT NULL
             AND ts_b.sequence <= sb.seq
             AND ts_e.sequence > sb.seq
            THEN 1 ELSE 0
          END
        ) AS covered
      FROM seats s
      JOIN trips t ON t.id = p_trip_id AND t.vehicle_id = s.vehicle_id
      JOIN segment_bounds sb ON TRUE
      LEFT JOIN reservations r
        ON r.trip_id = p_trip_id
        AND r.seat_id = s.id
        AND r.status = 'active'
      LEFT JOIN trip_stations ts_b
        ON ts_b.trip_id = r.trip_id
        AND ts_b.station_id = r.board_station_id
      LEFT JOIN trip_stations ts_e
        ON ts_e.trip_id = r.trip_id
        AND ts_e.station_id = r.exit_station_id
      WHERE s.seat_type IN ('normal','foldable','wheelchair','driver','guide')
      GROUP BY s.id, sb.seq
    )
    SELECT
      s.id,
      s.label,
      s.row,
      s.seat_col,
      s.seat_type,
      s.pair_id,
      CASE
        WHEN COALESCE(SUM(ss.covered), 0) = 0 THEN 'free'
        WHEN MIN(ss.covered) = 1 THEN 'full'
        ELSE 'partial'
      END AS status
    FROM seats s
    JOIN trips t ON t.id = p_trip_id AND t.vehicle_id = s.vehicle_id
    LEFT JOIN seat_segments ss ON ss.seat_id = s.id
    WHERE s.seat_type IN ('normal','foldable','wheelchair','driver','guide')
    GROUP BY s.id, s.label, s.row, s.seat_col, s.seat_type, s.pair_id
    ORDER BY s.row, s.seat_col;
  END IF;
END$$

CREATE DEFINER=`priscomr_rezervariuser`@`%` PROCEDURE `sp_is_seat_free` (IN `p_trip_id` INT, IN `p_seat_id` INT, IN `p_board_station_id` INT, IN `p_exit_station_id` INT)   BEGIN
  DECLARE v_bseq INT DEFAULT NULL;
  DECLARE v_eseq INT DEFAULT NULL;

  SELECT ts.sequence INTO v_bseq
  FROM trip_stations ts
  WHERE ts.trip_id = p_trip_id AND ts.station_id = p_board_station_id
  LIMIT 1;

  SELECT ts.sequence INTO v_eseq
  FROM trip_stations ts
  WHERE ts.trip_id = p_trip_id AND ts.station_id = p_exit_station_id
  LIMIT 1;

  IF v_bseq IS NULL OR v_eseq IS NULL OR v_bseq >= v_eseq THEN
    SELECT 0 AS is_free;
  ELSE
    SELECT CASE WHEN EXISTS (
      SELECT 1
      FROM reservations r
      JOIN trip_stations ts_b ON ts_b.trip_id = r.trip_id AND ts_b.station_id = r.board_station_id
      JOIN trip_stations ts_e ON ts_e.trip_id = r.trip_id AND ts_e.station_id = r.exit_station_id
      WHERE r.trip_id = p_trip_id
        AND r.seat_id = p_seat_id
        AND r.status = 'active'
        AND NOT (ts_e.sequence <= v_bseq OR ts_b.sequence >= v_eseq)
    ) THEN 0 ELSE 1 END AS is_free;
  END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `agencies`
--

CREATE TABLE `agencies` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `agent_chat_messages`
--

CREATE TABLE `agent_chat_messages` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `author_name` varchar(255) NOT NULL,
  `role` varchar(50) NOT NULL,
  `content` text DEFAULT NULL,
  `attachment_url` text DEFAULT NULL,
  `attachment_type` enum('image','link') DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `agent_chat_messages`
--

INSERT INTO `agent_chat_messages` (`id`, `user_id`, `author_name`, `role`, `content`, `attachment_url`, `attachment_type`, `created_at`) VALUES
(1, 1, 'admin', 'admin', 'salut', NULL, NULL, '2025-10-29 14:35:00'),
(2, 3, 'anca', 'agent', 'buna', NULL, NULL, '2025-10-29 14:35:25'),
(3, 1, 'admin', 'admin', NULL, '/uploads/1761749671765_glwq9l.jpg', 'image', '2025-10-29 14:54:32'),
(4, 1, 'admin', 'admin', NULL, '/uploads/1761749712972_ey0u9n.png', 'image', '2025-10-29 14:55:13'),
(5, 1, 'admin', 'admin', NULL, 'http://localhost:5000/uploads/1761749871010_t65q7d.jpg', 'image', '2025-10-29 14:57:51');

-- --------------------------------------------------------

--
-- Table structure for table `app_settings`
--

CREATE TABLE `app_settings` (
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `app_settings`
--

INSERT INTO `app_settings` (`setting_key`, `setting_value`, `updated_at`) VALUES
('receipt_note', 'test', '2025-10-28 14:00:35');

-- --------------------------------------------------------

--
-- Table structure for table `audit_logs`
--

CREATE TABLE `audit_logs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `actor_id` bigint(20) DEFAULT NULL,
  `entity` varchar(64) NOT NULL,
  `entity_id` bigint(20) DEFAULT NULL,
  `action` varchar(64) NOT NULL,
  `related_entity` varchar(64) DEFAULT 'reservation',
  `related_id` bigint(20) DEFAULT NULL,
  `correlation_id` char(36) DEFAULT NULL,
  `channel` enum('online','agent') DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `payment_method` enum('cash','card','online') DEFAULT NULL,
  `transaction_id` varchar(128) DEFAULT NULL,
  `note` varchar(255) DEFAULT NULL,
  `before_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`before_json`)),
  `after_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`after_json`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_logs`
--

INSERT INTO `audit_logs` (`id`, `created_at`, `actor_id`, `entity`, `entity_id`, `action`, `related_entity`, `related_id`, `correlation_id`, `channel`, `amount`, `payment_method`, `transaction_id`, `note`, `before_json`, `after_json`) VALUES
(1, '2025-10-24 16:17:11', 1, 'reservation', 1, 'reservation.create', 'reservation', NULL, 'a2c826f8-8138-4c1c-988d-e3c86f0f9ee5', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(2, '2025-10-24 16:17:20', 2, 'reservation', 2, 'reservation.create', 'reservation', NULL, '8c9d71dc-f90f-4636-a45f-2d29d4c2ca63', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(3, '2025-10-24 16:20:35', 1, 'reservation', 3, 'reservation.create', 'reservation', NULL, '45b65360-d1ce-4e26-8e80-d44a950053e8', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(4, '2025-10-24 16:23:16', 1, 'reservation', 4, 'reservation.create', 'reservation', NULL, 'e937ba5d-12c6-4c07-a22f-288f0b192f84', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(5, '2025-10-24 16:23:32', 1, 'reservation', 5, 'reservation.create', 'reservation', NULL, 'ced9c998-0053-4d79-b661-88b736a8cae7', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(6, '2025-10-24 16:23:39', 1, 'reservation', 6, 'reservation.create', 'reservation', NULL, '575101f9-3c4b-41d6-8fb1-1f7505165943', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(7, '2025-10-24 16:24:04', 1, 'reservation', 7, 'reservation.create', 'reservation', NULL, '9b3e4ac3-00e4-439b-b2b3-61be829e4437', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(8, '2025-10-24 16:24:10', 1, 'reservation', 8, 'reservation.create', 'reservation', NULL, 'b31819f1-f3ce-4450-aae3-b7c502e33fb1', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(9, '2025-10-24 16:25:03', 1, 'reservation', 5, 'reservation.cancel', 'reservation', NULL, '74d4f257-b432-4a37-a5a1-67ef8a60903c', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(10, '2025-10-24 16:25:05', 1, 'reservation', 9, 'reservation.create', 'reservation', NULL, 'a5a1f7fe-b4a5-4ea5-b69a-502bceded4d4', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(11, '2025-10-24 16:27:58', 1, 'reservation', 3, 'reservation.cancel', 'reservation', NULL, '59921719-cccf-4bc8-af4c-2b2d3e3fe316', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(12, '2025-10-24 16:27:59', 1, 'reservation', 10, 'reservation.create', 'reservation', NULL, '26868563-3a42-431e-9677-b80b03325aea', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(13, '2025-10-24 18:10:59', 1, 'reservation', 11, 'reservation.create', 'reservation', NULL, '079fbc2b-3c46-47e7-882e-c4a7593ec05d', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(14, '2025-10-26 21:41:18', 1, 'reservation', 12, 'reservation.create', 'reservation', NULL, '4056b704-95d8-4b6f-a434-cb323bff2b7d', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(15, '2025-10-26 21:53:22', 1, 'reservation', 13, 'reservation.create', 'reservation', NULL, '4f73176a-a069-4ee8-bf4b-7f3c1f280753', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(16, '2025-10-27 09:03:40', 1, 'reservation', 14, 'reservation.create', 'reservation', NULL, 'a6a1d137-1ff5-4635-ace0-af3f114553fe', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(17, '2025-10-27 09:03:51', 1, 'reservation', 15, 'reservation.create', 'reservation', NULL, '54a65746-adaf-4c97-801f-d5914141d3c2', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(18, '2025-10-27 09:05:20', 1, 'reservation', 16, 'reservation.create', 'reservation', NULL, 'b40504ff-97c6-4322-ae20-14e463999893', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(19, '2025-10-27 09:05:43', 1, 'reservation', 17, 'reservation.create', 'reservation', NULL, 'ebad744d-f6eb-4dae-af9d-6d73adf72cf9', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(20, '2025-10-27 09:08:36', 1, 'reservation', 18, 'reservation.create', 'reservation', NULL, '17b1515a-ae19-4fa0-8c41-c01a9674a661', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(21, '2025-10-27 12:53:23', 1, 'reservation', 19, 'reservation.create', 'reservation', NULL, '28f0c23e-b6cd-449a-a31f-d4f32c389d57', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(22, '2025-10-27 12:56:11', 1, 'reservation', 20, 'reservation.create', 'reservation', NULL, '7f793b8d-5d4d-4aac-ae03-c71a8dc55cb2', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(23, '2025-10-27 12:56:23', 1, 'reservation', 21, 'reservation.create', 'reservation', NULL, 'e31fe25e-e8d3-4b48-ae32-42214bce6176', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(24, '2025-10-27 13:01:01', 1, 'reservation', 22, 'reservation.create', 'reservation', NULL, '3081dfcb-a343-4fbc-9074-ff8ff63860c1', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(25, '2025-10-27 13:01:09', 1, 'reservation', 23, 'reservation.create', 'reservation', NULL, '4fd2fa45-4699-49e7-a82b-e0e165a0e130', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(26, '2025-10-27 13:01:18', 1, 'reservation', 24, 'reservation.create', 'reservation', NULL, '11fd7e0b-f6e3-4188-b6e8-442c8b753c4c', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(27, '2025-10-27 13:10:17', 1, 'reservation', 25, 'reservation.create', 'reservation', NULL, 'f06706eb-d73f-4639-b2a7-ce93932b5c6d', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(28, '2025-10-27 13:10:26', 1, 'reservation', 26, 'reservation.create', 'reservation', NULL, '2f7429b0-a84d-4350-8ac0-919540c4e301', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(29, '2025-10-27 13:11:37', 1, 'reservation', 27, 'reservation.create', 'reservation', NULL, '1acf91ef-3d24-4b49-a5af-0ed756fe87f7', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(30, '2025-10-27 13:36:45', 1, 'reservation', 28, 'reservation.create', 'reservation', NULL, 'cb23b1e5-dbad-4e3e-8db2-729037725f4d', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(31, '2025-10-27 13:51:36', 1, 'reservation', 29, 'reservation.create', 'reservation', NULL, '3f6e5d05-0b65-4fa7-a9e0-aa9bc7483b2b', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(32, '2025-10-27 14:11:03', 1, 'reservation', 30, 'reservation.create', 'reservation', NULL, '9c9bf746-3924-4069-916e-fb07902b7c51', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(33, '2025-10-27 15:34:00', 1, 'reservation', NULL, 'reservation.create', 'reservation', NULL, '8e65490e-aca6-4d47-ab95-7b9d13b03bd1', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(34, '2025-10-27 15:34:39', 1, 'reservation', NULL, 'reservation.create', 'reservation', NULL, '8703c15e-631d-489c-ae1d-948793f6b351', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(35, '2025-10-27 15:36:37', 1, 'reservation', NULL, 'reservation.create', 'reservation', NULL, '28b6cf7e-7f7a-43b3-9965-f3fbdf0d9c66', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(36, '2025-10-27 15:39:21', 1, 'reservation', 37, 'reservation.create', 'reservation', NULL, '5198dcb3-07f2-458b-9b81-9375425e4f79', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(37, '2025-10-27 15:39:33', 1, 'reservation', 38, 'reservation.create', 'reservation', NULL, '67f4df20-869e-4e94-b96e-df8224725848', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(38, '2025-10-27 15:39:46', 1, 'reservation', 39, 'reservation.create', 'reservation', NULL, 'e1316856-6401-454d-86bf-19e97439888b', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(39, '2025-10-27 18:00:27', 3, 'reservation', 40, 'reservation.create', 'reservation', NULL, 'fc6a108c-33f4-4255-9e71-195f185820db', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(40, '2025-10-27 18:05:07', 1, 'reservation', 41, 'reservation.create', 'reservation', NULL, '7cb5d948-cf75-4fdb-a135-5c236982c3fe', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(41, '2025-10-27 19:40:03', 1, 'reservation', 42, 'reservation.create', 'reservation', NULL, '4d2ee45c-a60e-4907-9af4-a00fc796d2a4', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(42, '2025-10-28 11:01:07', 1, 'reservation', 40, 'reservation.move', 'reservation', 40, 'dc53b4e1-f41e-4133-a2d8-9623d9f11c59', NULL, NULL, NULL, NULL, 'from_trip_id=1738;from_seat_id=25;from_board=1;from_exit=2', NULL, NULL),
(43, '2025-10-28 11:01:24', 1, 'reservation', 40, 'reservation.cancel', 'reservation', NULL, 'fdb371d4-4c57-4076-bd59-83e5084f612a', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(44, '2025-10-28 11:01:24', 1, 'reservation', 43, 'reservation.create', 'reservation', 40, 'fdb371d4-4c57-4076-bd59-83e5084f612a', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(45, '2025-10-28 11:01:24', 1, 'reservation', 43, 'reservation.move', 'reservation', 40, 'fdb371d4-4c57-4076-bd59-83e5084f612a', 'agent', NULL, NULL, NULL, NULL, NULL, NULL),
(46, '2025-10-28 12:46:15', 1, 'reservation', 44, 'reservation.create', 'reservation', NULL, '5241b7a8-bab7-4505-9390-e47db49f4b3e', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(47, '2025-10-28 12:48:40', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, 'ba520916-1067-4aa7-924b-931cfdffb00b', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=25;from_board=1;from_exit=2', NULL, NULL),
(48, '2025-10-28 12:48:57', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, 'a5ed637e-9a12-4b47-9a41-961a3fad6cb7', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=26;from_board=1;from_exit=2', NULL, NULL),
(49, '2025-10-28 12:49:30', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, '66e22458-0804-421b-85a1-ab2acea6dd89', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=25;from_board=1;from_exit=2', NULL, NULL),
(50, '2025-10-28 13:02:08', 2, 'reservation', 45, 'reservation.create', 'reservation', NULL, '5f694667-0184-420d-aebf-50e2b56e0653', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(51, '2025-10-28 13:18:35', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, '2f21388b-b7e6-40cc-b247-fe2d5b4d2e7e', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=28;from_board=1;from_exit=2', NULL, NULL),
(52, '2025-10-28 13:18:46', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, 'f58cdf43-dbd2-47ce-ba98-7972063cc305', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=29;from_board=1;from_exit=2', NULL, NULL),
(53, '2025-10-28 13:19:20', 3, 'reservation', 46, 'reservation.create', 'reservation', NULL, 'bbfbfe09-1ce5-40f8-b354-31d61387606e', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(54, '2025-10-28 13:19:25', 3, 'reservation', 47, 'reservation.create', 'reservation', NULL, '8c0356e1-4e71-4838-bfb0-0973952499e9', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(55, '2025-10-28 14:20:19', 1, 'reservation', 48, 'reservation.create', 'reservation', NULL, '7675bb20-2e35-420c-b256-7dc18c9fe3d0', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(56, '2025-10-28 14:21:47', 1, 'reservation', 49, 'reservation.create', 'reservation', NULL, '3bfcbe78-21f8-4c14-a9c0-98b6b952997e', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(57, '2025-10-28 14:22:25', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, '6b91794e-488a-48d4-882c-861cdfaa4049', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=31;from_board=1;from_exit=2', NULL, NULL),
(58, '2025-10-28 14:22:30', 3, 'reservation', 44, 'reservation.move', 'reservation', 44, 'b41df828-2a20-4948-aa90-608f3e69f780', NULL, NULL, NULL, NULL, 'from_trip_id=1750;from_seat_id=32;from_board=1;from_exit=2', NULL, NULL),
(59, '2025-10-28 14:36:19', 1, 'reservation', 50, 'reservation.create', 'reservation', NULL, '62d73821-43a6-41bd-884a-590c2aefc103', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(60, '2025-10-28 14:36:40', 1, 'reservation', 51, 'reservation.create', 'reservation', NULL, '5b8b69fa-f5bd-4499-819c-3442af28e0b4', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(61, '2025-10-28 14:37:29', 1, 'person', 24, 'person.noshow.add', 'reservation', 48, 'f090d6ed-b60b-40a9-8935-1ca24dcd55d1', 'agent', NULL, NULL, NULL, 'trip_id=1750;seat_id=26;board_station_id=1;exit_station_id=3', NULL, NULL),
(62, '2025-10-28 14:38:20', 1, 'person', 24, 'person.blacklist.add', NULL, NULL, '8beb9d8d-81b4-49a0-ac40-d5f9a224a8e0', 'agent', NULL, NULL, NULL, 'Are multe neprezentari', NULL, NULL),
(63, '2025-10-28 15:36:29', 1, 'reservation', 45, 'reservation.cancel', 'reservation', NULL, '362033e2-b662-45c7-9a55-13e31f498f38', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(64, '2025-10-28 15:36:29', 1, 'reservation', 52, 'reservation.create', 'reservation', 45, '362033e2-b662-45c7-9a55-13e31f498f38', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(65, '2025-10-28 15:36:29', 1, 'reservation', 52, 'reservation.move', 'reservation', 45, '362033e2-b662-45c7-9a55-13e31f498f38', 'agent', NULL, NULL, NULL, NULL, NULL, NULL),
(66, '2025-10-28 15:37:40', 1, 'reservation', 53, 'reservation.create', 'reservation', NULL, '761c2852-0fbc-4064-b34a-531ac90ab9f6', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(67, '2025-10-28 15:38:07', 1, 'reservation', 54, 'reservation.create', 'reservation', NULL, 'a6ebebee-e197-46c7-a3a2-62600d99da43', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(68, '2025-10-28 16:23:44', 1, 'reservation', 55, 'reservation.create', 'reservation', NULL, '8ab05d4d-6060-48e5-9110-cd4a4d9339b9', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(69, '2025-10-28 20:31:51', 1, 'reservation', 56, 'reservation.create', 'reservation', NULL, 'a4a9bc0d-c124-4288-8ae6-9d88b070db0e', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(70, '2025-10-30 12:54:23', 1, 'reservation', 57, 'reservation.create', 'reservation', NULL, 'ae36dfbc-c6fe-47b3-8853-9d03d0e6606f', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(71, '2025-10-30 12:54:33', 1, 'reservation', 58, 'reservation.create', 'reservation', NULL, '19241043-de0d-403b-9372-3e213c500042', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(72, '2025-10-30 12:54:42', 1, 'reservation', 59, 'reservation.create', 'reservation', NULL, '54640d24-c460-4f60-986b-841803cacd92', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(73, '2025-10-30 12:54:46', 1, 'reservation', 59, 'reservation.move', 'reservation', 59, 'c8d23caa-0fdd-484e-baf1-d9a91f380349', NULL, NULL, NULL, NULL, 'from_trip_id=1774;from_seat_id=27;from_board=1;from_exit=2', NULL, NULL),
(74, '2025-10-30 12:55:28', 1, 'reservation', 59, 'reservation.cancel', 'reservation', NULL, 'd08963e7-fa9e-4cde-8aa5-5a1b755b84a0', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(75, '2025-10-30 14:32:13', 1, 'reservation', 60, 'reservation.create', 'reservation', NULL, '8088dbc6-fa5a-4808-8d3d-f8b46df7c4b6', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(76, '2025-10-30 14:32:13', 1, 'reservation', 61, 'reservation.create', 'reservation', NULL, '676ec43a-d962-4b04-a760-7532d2b28fbe', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(77, '2025-10-30 14:32:13', 1, 'reservation', 62, 'reservation.create', 'reservation', NULL, '94a4f076-dd85-4e7d-9a3b-b5799f792e90', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(78, '2025-10-30 15:49:44', 1, 'reservation', 65, 'reservation.create', 'reservation', NULL, '459e625d-a1b5-4c5f-b53e-7a857f0f48b1', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(79, '2025-10-30 15:52:59', 1, 'reservation', 66, 'reservation.create', 'reservation', NULL, '1f49685a-6453-4387-8e34-15a78b2a2e08', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(80, '2025-10-30 15:57:33', 1, 'reservation', 67, 'reservation.create', 'reservation', NULL, 'f413f96b-fa44-426a-b1d3-ce3bbdfa58cc', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(81, '2025-10-30 15:57:40', 1, 'reservation', 68, 'reservation.create', 'reservation', NULL, 'c71697ca-e13f-452c-9e83-72d11a914aaf', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(82, '2025-10-30 21:21:45', 1, 'reservation', 69, 'reservation.create', 'reservation', NULL, '43e01082-364b-40ba-a97f-ce69138992e4', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(83, '2025-10-30 21:26:15', 1, 'reservation', 70, 'reservation.create', 'reservation', NULL, 'ac3e04fc-54f0-4f6c-94b6-cc2af428a97f', NULL, NULL, NULL, NULL, NULL, NULL, NULL),
(84, '2025-10-30 23:08:17', 1, 'reservation', 71, 'reservation.create', 'reservation', NULL, '75a14043-4d27-481a-a542-38650bc9340c', NULL, NULL, NULL, NULL, NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `blacklist`
--

CREATE TABLE `blacklist` (
  `id` int(11) NOT NULL,
  `person_id` int(11) DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `added_by_employee_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `blacklist`
--

INSERT INTO `blacklist` (`id`, `person_id`, `reason`, `added_by_employee_id`, `created_at`) VALUES
(1, 24, 'Are multe neprezentari', 1, '2025-10-28 14:38:20');

-- --------------------------------------------------------

--
-- Table structure for table `cash_handovers`
--

CREATE TABLE `cash_handovers` (
  `id` int(11) NOT NULL,
  `employee_id` int(11) DEFAULT NULL,
  `operator_id` int(11) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `discount_types`
--

CREATE TABLE `discount_types` (
  `id` int(11) NOT NULL,
  `code` varchar(50) NOT NULL,
  `label` text NOT NULL,
  `value_off` decimal(5,2) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `type` enum('percent','fixed') NOT NULL DEFAULT 'percent'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `discount_types`
--

INSERT INTO `discount_types` (`id`, `code`, `label`, `value_off`, `created_at`, `type`) VALUES
(1, 'PEN', 'Pensionar', 50.00, '2025-10-28 18:52:28', 'percent');

-- --------------------------------------------------------

--
-- Table structure for table `employees`
--

CREATE TABLE `employees` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `password_hash` text DEFAULT NULL,
  `role` enum('driver','agent','operator_admin','admin') NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `operator_id` int(11) NOT NULL DEFAULT 1,
  `agency_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `employees`
--

INSERT INTO `employees` (`id`, `name`, `phone`, `email`, `password_hash`, `role`, `active`, `created_at`, `operator_id`, `agency_id`) VALUES
(1, 'admin', '0743171315', NULL, '$2a$12$eZZLP5AOlQJuOl/5ctwDeOp0avF8iY5zfIadvp1v7P9U7oTZDoPfe', 'admin', 1, '2025-08-04 13:46:37', 2, 1),
(2, 'lavinia', '0742852790', NULL, '$2a$12$qw5jN.PIZnNt05E13z5kQ.jrEbNUyxe6nl.vywLHPC3ivk6LYuLr.', 'agent', 1, '2025-10-24 15:56:33', 2, 1),
(3, 'anca', '0735612518', NULL, '$2a$12$X4k3hTLHV3MW0pW7vhjjhes2jaXIg1gI5ikr0kWhbqFTUqUbpWkQ6', 'agent', 1, '2025-10-27 13:41:58', 2, 1),
(4, 'daniel', '', '', NULL, 'agent', 1, '2025-10-28 18:35:49', 2, NULL),
(5, 'test', NULL, 'madafaka_mw@yahoo.com', '$2a$12$Z6u0/gWZnrNzDwS9Hy4BZOAmnx0juWmNrYJ55hNcmtodSOpXBMOhG', 'driver', 0, '2025-10-28 18:49:27', 2, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `idempotency_keys`
--

CREATE TABLE `idempotency_keys` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `idem_key` varchar(128) NOT NULL,
  `reservation_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `idempotency_keys`
--

INSERT INTO `idempotency_keys` (`id`, `user_id`, `idem_key`, `reservation_id`, `created_at`) VALUES
(1, 1, 'ea2cdbc7-7ed0-44ca-99dd-5c4977d9395f', 44, '2025-10-28 12:46:15'),
(2, 2, 'res-1761649329096-7fiolu78', 45, '2025-10-28 13:02:08'),
(4, 3, 'ec7d93f3-49ce-4669-9ec8-6332caa6e715', 46, '2025-10-28 13:19:20'),
(5, 3, '94c9cdd5-1a18-4ef5-9013-b18442e3df39', 47, '2025-10-28 13:19:25'),
(6, 1, 'f3588e34-a5c4-4f7d-aa55-60b6f2a31d6c', 48, '2025-10-28 14:20:19'),
(7, 1, 'e29e0cf4-29fe-49f7-8c59-fa1ab1a3416b', 49, '2025-10-28 14:21:47'),
(8, 1, 'b0953654-ad4f-4181-bf5d-f87cdaad3e2b', 50, '2025-10-28 14:36:19'),
(9, 1, '7160e973-bb34-467d-8c98-f6c6934f607f', 51, '2025-10-28 14:36:40'),
(10, 1, '60f28fd4-c642-4b0f-9cad-d67d8eb9f9cf', 53, '2025-10-28 15:37:40'),
(11, 1, '082e87d0-4fce-403e-9e7a-e7be3f33e87e', 54, '2025-10-28 15:38:07'),
(12, 1, '90442c3e-f16b-4178-b8c5-89b00b899882', 55, '2025-10-28 16:23:44'),
(13, 1, 'a727a002-b6ae-4621-9fcc-205d9a364716', 56, '2025-10-28 20:31:51'),
(14, 1, '697f2a66-8e02-45c0-8fd7-e6acd1a5bbea', 57, '2025-10-30 12:54:23'),
(15, 1, '0b289757-1cc9-4291-a109-04e1b757c182', 58, '2025-10-30 12:54:33'),
(16, 1, '8d030e6d-2573-4fe1-bc50-89d51f97c484', 59, '2025-10-30 12:54:42'),
(17, 1, '71bcbcf6-329b-438a-aa1c-7019819621e2', 60, '2025-10-30 14:32:13'),
(21, 1, '1fb4da53-293a-4744-af16-cc80fd3f88c6', 67, '2025-10-30 15:57:33'),
(22, 1, 'f0acd4fc-478f-4c68-9171-e62b6cb1925b', 68, '2025-10-30 15:57:40'),
(23, 1, '94e36603-3249-4494-8ad7-a6d053680dc7', 69, '2025-10-30 21:21:45'),
(24, 1, 'e3c34738-f9ac-48cf-b955-b14c79cb7f41', 70, '2025-10-30 21:26:15'),
(25, 1, '255c2c25-fd0e-4c0c-a50d-f6bdce6a9a76', 71, '2025-10-30 23:08:17');

-- --------------------------------------------------------

--
-- Table structure for table `invitations`
--

CREATE TABLE `invitations` (
  `id` int(11) NOT NULL,
  `token` varchar(255) NOT NULL,
  `role` enum('driver','agent','operator_admin','admin') NOT NULL,
  `operator_id` int(11) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `expires_at` datetime NOT NULL,
  `created_by` int(11) DEFAULT NULL,
  `used_at` datetime DEFAULT NULL,
  `used_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `invitations`
--

INSERT INTO `invitations` (`id`, `token`, `role`, `operator_id`, `email`, `expires_at`, `created_by`, `used_at`, `used_by`) VALUES
(1, 'bQ3E6F6hLnwFAHwuyn0B2M0kpx1AepxurodJ4jmurjc', 'agent', 2, 'madafaka_mw@yahoo.com', '2025-10-31 18:48:47', 1, '2025-10-28 18:49:27', 5);

-- --------------------------------------------------------

--
-- Table structure for table `no_shows`
--

CREATE TABLE `no_shows` (
  `id` int(11) NOT NULL,
  `person_id` int(11) DEFAULT NULL,
  `trip_id` int(11) DEFAULT NULL,
  `seat_id` int(11) DEFAULT NULL,
  `reservation_id` int(11) DEFAULT NULL,
  `board_station_id` int(11) DEFAULT NULL,
  `exit_station_id` int(11) DEFAULT NULL,
  `added_by_employee_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `no_shows`
--

INSERT INTO `no_shows` (`id`, `person_id`, `trip_id`, `seat_id`, `reservation_id`, `board_station_id`, `exit_station_id`, `added_by_employee_id`, `created_at`) VALUES
(1, 24, 1750, 26, 48, 1, 3, 1, '2025-10-28 14:37:29');

-- --------------------------------------------------------

--
-- Table structure for table `operators`
--

CREATE TABLE `operators` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `pos_endpoint` text NOT NULL,
  `theme_color` varchar(7) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `operators`
--

INSERT INTO `operators` (`id`, `name`, `pos_endpoint`, `theme_color`) VALUES
(1, 'Pris-Com', 'https://pos.priscom.ro/pay', '#FF0000'),
(2, 'Auto-Dimas', 'https://pos.autodimas.ro/pay', '#0000FF');

-- --------------------------------------------------------

--
-- Table structure for table `payments`
--

CREATE TABLE `payments` (
  `id` int(11) NOT NULL,
  `reservation_id` int(11) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `status` enum('pending','paid','failed') NOT NULL DEFAULT 'pending',
  `payment_method` varchar(20) DEFAULT NULL,
  `transaction_id` text DEFAULT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  `deposited_at` date DEFAULT NULL,
  `deposited_by` int(11) DEFAULT NULL,
  `collected_by` int(11) DEFAULT NULL,
  `cash_handover_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people`
--

CREATE TABLE `people` (
  `id` int(11) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `owner_status` enum('active','pending','hidden') NOT NULL DEFAULT 'active',
  `prev_owner_id` int(11) DEFAULT NULL,
  `replaced_by_id` int(11) DEFAULT NULL,
  `owner_changed_by` int(11) DEFAULT NULL,
  `owner_changed_at` datetime DEFAULT NULL,
  `blacklist` tinyint(1) NOT NULL DEFAULT 0,
  `whitelist` tinyint(1) NOT NULL DEFAULT 0,
  `notes` text DEFAULT NULL,
  `notes_by` int(11) DEFAULT NULL,
  `notes_at` datetime DEFAULT NULL,
  `is_active` tinyint(1) GENERATED ALWAYS AS (case when `owner_status` = 'active' then 1 else NULL end) STORED,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `people`
--

INSERT INTO `people` (`id`, `name`, `phone`, `owner_status`, `prev_owner_id`, `replaced_by_id`, `owner_changed_by`, `owner_changed_at`, `blacklist`, `whitelist`, `notes`, `notes_by`, `notes_at`, `updated_at`) VALUES
(31, 'test', NULL, 'active', NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, NULL, '2025-10-30 21:21:45');

-- --------------------------------------------------------

--
-- Table structure for table `price_lists`
--

CREATE TABLE `price_lists` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `version` int(11) NOT NULL DEFAULT 1,
  `effective_from` date NOT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `route_id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `price_lists`
--

INSERT INTO `price_lists` (`id`, `name`, `version`, `effective_from`, `created_by`, `created_at`, `route_id`, `category_id`) VALUES
(1, '1-1-2025-10-24', 1, '2025-10-24', 1, '2025-10-24 16:14:02', 1, 1),
(2, '1-1-2025-10-27', 1, '2025-10-27', 1, '2025-10-27 09:26:32', 1, 1),
(3, '1-1-2025-10-31', 1, '2025-10-31', 1, '2025-10-27 11:40:34', 1, 1),
(4, '1-2-2025-10-30', 1, '2025-10-30', 1, '2025-10-30 16:06:45', 1, 2),
(5, '1-1-2025-10-30', 1, '2025-10-30', 1, '2025-10-30 17:08:02', 1, 1),
(6, '2-2-2025-10-30', 1, '2025-10-30', 1, '2025-10-30 17:11:07', 2, 2);

-- --------------------------------------------------------

--
-- Table structure for table `price_list_items`
--

CREATE TABLE `price_list_items` (
  `id` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `currency` varchar(5) NOT NULL DEFAULT 'RON',
  `price_return` decimal(10,2) DEFAULT NULL,
  `price_list_id` int(11) DEFAULT NULL,
  `from_station_id` int(11) NOT NULL,
  `to_station_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `price_list_items`
--

INSERT INTO `price_list_items` (`id`, `price`, `currency`, `price_return`, `price_list_id`, `from_station_id`, `to_station_id`) VALUES
(229, 1.00, 'RON', 4.00, 3, 1, 4),
(230, 1.00, 'RON', 4.00, 3, 4, 1),
(231, 2.00, 'RON', 5.00, 3, 1, 3),
(232, 2.00, 'RON', 5.00, 3, 3, 1),
(233, 5.00, 'RON', NULL, 3, 1, 2),
(234, 3.00, 'RON', NULL, 3, 2, 1),
(235, 10000.00, 'RON', NULL, 3, 2, 4),
(236, 1.00, 'RON', NULL, 2, 1, 4),
(237, 1.00, 'RON', NULL, 2, 4, 1),
(238, 2.00, 'RON', NULL, 2, 1, 3),
(239, 2.00, 'RON', NULL, 2, 3, 1),
(240, 3.00, 'RON', NULL, 2, 1, 2),
(241, 3.00, 'RON', NULL, 2, 2, 1),
(242, 1.00, 'RON', NULL, 2, 4, 3),
(243, 1.00, 'RON', NULL, 2, 3, 4),
(244, 2.00, 'RON', NULL, 2, 4, 2),
(245, 2.00, 'RON', NULL, 2, 2, 4),
(246, 1.00, 'RON', NULL, 2, 3, 2),
(247, 1.00, 'RON', NULL, 2, 2, 3),
(251, 1.00, 'RON', NULL, 5, 1, 4),
(252, 1.00, 'RON', NULL, 5, 4, 1),
(253, 2.00, 'RON', NULL, 5, 1, 3),
(254, 2.00, 'RON', NULL, 5, 3, 1),
(255, 3.00, 'RON', NULL, 5, 1, 2),
(256, 3.00, 'RON', NULL, 5, 2, 1),
(257, 1.00, 'RON', NULL, 5, 4, 3),
(258, 1.00, 'RON', NULL, 5, 3, 4),
(259, 2.00, 'RON', NULL, 5, 4, 2),
(260, 2.00, 'RON', NULL, 5, 2, 4),
(261, 1.00, 'RON', NULL, 5, 3, 2),
(262, 1.00, 'RON', NULL, 5, 2, 3),
(267, 10.00, 'RON', NULL, 6, 2, 5),
(268, 10.00, 'RON', NULL, 6, 5, 2),
(271, 100.00, 'RON', NULL, 4, 1, 2),
(272, 100.00, 'RON', NULL, 4, 2, 1);

-- --------------------------------------------------------

--
-- Table structure for table `pricing_categories`
--

CREATE TABLE `pricing_categories` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `pricing_categories`
--

INSERT INTO `pricing_categories` (`id`, `name`, `description`, `active`) VALUES
(1, 'Normal', 'Preț standard pentru bilete individuale', 1),
(2, 'Online', 'Preț standard pentru bilete online', 1),
(3, 'Student', 'Preț standard pentru studenți', 1);

-- --------------------------------------------------------

--
-- Table structure for table `promo_codes`
--

CREATE TABLE `promo_codes` (
  `id` int(11) NOT NULL,
  `code` varchar(50) NOT NULL,
  `label` text NOT NULL,
  `type` enum('percent','fixed') NOT NULL,
  `value_off` decimal(7,2) NOT NULL,
  `valid_from` datetime DEFAULT NULL,
  `valid_to` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `channels` set('online','agent') NOT NULL DEFAULT 'online',
  `min_price` decimal(10,2) DEFAULT NULL,
  `max_discount` decimal(10,2) DEFAULT NULL,
  `max_total_uses` int(11) DEFAULT NULL,
  `max_uses_per_person` int(11) DEFAULT NULL,
  `combinable` tinyint(1) NOT NULL DEFAULT 0,
  `created_by` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `promo_codes`
--

INSERT INTO `promo_codes` (`id`, `code`, `label`, `type`, `value_off`, `valid_from`, `valid_to`, `active`, `channels`, `min_price`, `max_discount`, `max_total_uses`, `max_uses_per_person`, `combinable`, `created_by`, `created_at`) VALUES
(1, 'TEST', 'test', 'percent', 50.00, NULL, NULL, 1, 'agent', NULL, NULL, NULL, NULL, 0, NULL, '2025-10-30 16:09:38');

-- --------------------------------------------------------

--
-- Table structure for table `promo_code_hours`
--

CREATE TABLE `promo_code_hours` (
  `promo_code_id` int(11) NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo_code_routes`
--

CREATE TABLE `promo_code_routes` (
  `promo_code_id` int(11) NOT NULL,
  `route_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo_code_schedules`
--

CREATE TABLE `promo_code_schedules` (
  `promo_code_id` int(11) NOT NULL,
  `route_schedule_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo_code_usages`
--

CREATE TABLE `promo_code_usages` (
  `id` int(11) NOT NULL,
  `promo_code_id` int(11) NOT NULL,
  `reservation_id` int(11) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `used_at` datetime NOT NULL DEFAULT current_timestamp(),
  `discount_amount` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo_code_weekdays`
--

CREATE TABLE `promo_code_weekdays` (
  `promo_code_id` int(11) NOT NULL,
  `weekday` tinyint(1) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reservations`
--

CREATE TABLE `reservations` (
  `id` int(11) NOT NULL,
  `trip_id` int(11) DEFAULT NULL,
  `seat_id` int(11) DEFAULT NULL,
  `person_id` int(11) DEFAULT NULL,
  `reservation_time` timestamp NULL DEFAULT current_timestamp(),
  `status` enum('active','cancelled') NOT NULL DEFAULT 'active',
  `observations` text DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `board_station_id` int(11) NOT NULL,
  `exit_station_id` int(11) NOT NULL,
  `version` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `reservations`
--

INSERT INTO `reservations` (`id`, `trip_id`, `seat_id`, `person_id`, `reservation_time`, `status`, `observations`, `created_by`, `board_station_id`, `exit_station_id`, `version`) VALUES
(70, 8867, 100, 31, '2025-10-30 19:26:15', 'active', NULL, 1, 1, 2, 0),
(71, 9092, 25, 31, '2025-10-30 21:08:17', 'active', NULL, 1, 1, 2, 0);

-- --------------------------------------------------------

--
-- Table structure for table `reservations_backup`
--

CREATE TABLE `reservations_backup` (
  `id` int(11) NOT NULL,
  `reservation_id` int(11) DEFAULT NULL,
  `trip_id` int(11) DEFAULT NULL,
  `seat_id` int(11) DEFAULT NULL,
  `label` text DEFAULT NULL,
  `person_id` int(11) DEFAULT NULL,
  `backup_time` datetime DEFAULT current_timestamp(),
  `old_vehicle_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reservation_discounts`
--

CREATE TABLE `reservation_discounts` (
  `id` int(11) NOT NULL,
  `reservation_id` int(11) NOT NULL,
  `discount_type_id` int(11) DEFAULT NULL,
  `promo_code_id` int(11) DEFAULT NULL,
  `discount_amount` decimal(10,2) NOT NULL,
  `applied_at` datetime NOT NULL DEFAULT current_timestamp(),
  `discount_snapshot` decimal(5,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reservation_events`
--

CREATE TABLE `reservation_events` (
  `id` int(11) NOT NULL,
  `reservation_id` int(11) NOT NULL,
  `action` enum('create','update','move','cancel','uncancel','delete','pay','refund') NOT NULL,
  `actor_id` int(11) DEFAULT NULL,
  `details` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`details`)),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reservation_intents`
--

CREATE TABLE `reservation_intents` (
  `id` int(11) NOT NULL,
  `trip_id` int(11) NOT NULL,
  `seat_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `reservation_pricing`
--

CREATE TABLE `reservation_pricing` (
  `reservation_id` int(11) NOT NULL,
  `price_value` decimal(10,2) NOT NULL,
  `price_list_id` int(11) NOT NULL,
  `pricing_category_id` int(11) NOT NULL,
  `booking_channel` enum('online','agent') NOT NULL DEFAULT 'agent',
  `employee_id` int(11) NOT NULL DEFAULT 12,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `reservation_pricing`
--

INSERT INTO `reservation_pricing` (`reservation_id`, `price_value`, `price_list_id`, `pricing_category_id`, `booking_channel`, `employee_id`, `created_at`, `updated_at`) VALUES
(69, 3.00, 5, 1, 'agent', 1, '2025-10-30 21:21:45', '2025-10-30 21:21:45'),
(70, 3.00, 5, 1, 'agent', 1, '2025-10-30 21:26:15', '2025-10-30 21:26:15'),
(71, 3.00, 5, 1, 'agent', 1, '2025-10-30 23:08:17', '2025-10-30 23:08:17');

-- --------------------------------------------------------

--
-- Table structure for table `routes`
--

CREATE TABLE `routes` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `order_index` int(11) DEFAULT NULL,
  `visible_in_reservations` tinyint(1) DEFAULT 1,
  `visible_for_drivers` tinyint(1) DEFAULT 1,
  `visible_online` tinyint(4) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `routes`
--

INSERT INTO `routes` (`id`, `name`, `order_index`, `visible_in_reservations`, `visible_for_drivers`, `visible_online`) VALUES
(1, 'Botoșani - Iași', NULL, 1, 1, 1),
(2, 'Iași - Botoșani - Dorohoi', NULL, 1, 1, 1);

-- --------------------------------------------------------

--
-- Table structure for table `route_schedules`
--

CREATE TABLE `route_schedules` (
  `id` int(11) NOT NULL,
  `route_id` int(11) NOT NULL,
  `departure` time NOT NULL,
  `operator_id` int(11) NOT NULL,
  `direction` enum('tur','retur') NOT NULL DEFAULT 'tur'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `route_schedules`
--

INSERT INTO `route_schedules` (`id`, `route_id`, `departure`, `operator_id`, `direction`) VALUES
(1, 1, '06:00:00', 1, 'tur'),
(2, 1, '07:00:00', 2, 'retur'),
(3, 1, '08:00:00', 2, 'tur'),
(4, 1, '09:00:00', 2, 'retur'),
(5, 1, '10:00:00', 2, 'tur'),
(6, 1, '11:00:00', 2, 'tur'),
(7, 2, '07:00:00', 2, 'retur'),
(8, 2, '10:00:00', 2, 'tur');

-- --------------------------------------------------------

--
-- Table structure for table `route_schedule_discounts`
--

CREATE TABLE `route_schedule_discounts` (
  `discount_type_id` int(11) NOT NULL,
  `route_schedule_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `route_schedule_discounts`
--

INSERT INTO `route_schedule_discounts` (`discount_type_id`, `route_schedule_id`) VALUES
(1, 1),
(1, 2),
(1, 3),
(1, 4),
(1, 5),
(1, 6),
(1, 7),
(1, 8);

-- --------------------------------------------------------

--
-- Table structure for table `route_schedule_pricing_categories`
--

CREATE TABLE `route_schedule_pricing_categories` (
  `route_schedule_id` int(11) NOT NULL,
  `pricing_category_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `route_schedule_pricing_categories`
--

INSERT INTO `route_schedule_pricing_categories` (`route_schedule_id`, `pricing_category_id`) VALUES
(1, 1),
(1, 3),
(2, 1),
(2, 3),
(3, 1),
(3, 3),
(4, 1),
(4, 3),
(5, 1),
(5, 3),
(6, 1),
(6, 3),
(7, 1),
(7, 3),
(8, 1),
(8, 3);

-- --------------------------------------------------------

--
-- Table structure for table `route_stations`
--

CREATE TABLE `route_stations` (
  `id` int(11) NOT NULL,
  `route_id` int(11) NOT NULL,
  `station_id` int(11) NOT NULL,
  `sequence` int(11) NOT NULL,
  `distance_from_previous_km` decimal(6,2) DEFAULT NULL,
  `travel_time_from_previous_minutes` int(11) DEFAULT NULL,
  `dwell_time_minutes` int(11) DEFAULT 0,
  `geofence_type` enum('circle','polygon') NOT NULL DEFAULT 'circle',
  `geofence_radius_m` decimal(10,2) DEFAULT NULL,
  `geofence_polygon` geometry DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `route_stations`
--

INSERT INTO `route_stations` (`id`, `route_id`, `station_id`, `sequence`, `distance_from_previous_km`, `travel_time_from_previous_minutes`, `dwell_time_minutes`, `geofence_type`, `geofence_radius_m`, `geofence_polygon`, `created_at`, `updated_at`) VALUES
(3, 1, 1, 1, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 09:25:53', '2025-10-27 09:25:53'),
(4, 1, 4, 2, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 09:25:53', '2025-10-27 09:25:53'),
(5, 1, 3, 3, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 09:25:53', '2025-10-27 09:25:53'),
(6, 1, 2, 4, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 09:25:53', '2025-10-27 09:25:53'),
(7, 2, 2, 1, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 13:59:22', '2025-10-27 13:59:22'),
(8, 2, 3, 2, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 13:59:22', '2025-10-27 13:59:22'),
(9, 2, 4, 3, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 13:59:22', '2025-10-27 13:59:22'),
(10, 2, 1, 4, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 13:59:22', '2025-10-27 13:59:22'),
(11, 2, 5, 5, NULL, NULL, 0, 'circle', 200.00, NULL, '2025-10-27 13:59:22', '2025-10-27 13:59:22');

-- --------------------------------------------------------

--
-- Table structure for table `schedule_exceptions`
--

CREATE TABLE `schedule_exceptions` (
  `id` int(11) NOT NULL,
  `schedule_id` int(11) NOT NULL,
  `exception_date` date DEFAULT NULL,
  `weekday` tinyint(3) UNSIGNED DEFAULT NULL,
  `disable_run` tinyint(1) NOT NULL DEFAULT 0,
  `disable_online` tinyint(1) NOT NULL DEFAULT 0,
  `created_by_employee_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `schedule_exceptions`
--

INSERT INTO `schedule_exceptions` (`id`, `schedule_id`, `exception_date`, `weekday`, `disable_run`, `disable_online`, `created_by_employee_id`, `created_at`) VALUES
(6, 7, NULL, NULL, 0, 0, 1, '2025-10-30 13:12:40'),
(8, 8, NULL, NULL, 0, 0, 1, '2025-10-30 13:13:38');

-- --------------------------------------------------------

--
-- Table structure for table `seats`
--

CREATE TABLE `seats` (
  `id` int(11) NOT NULL,
  `vehicle_id` int(11) DEFAULT NULL,
  `seat_number` int(11) DEFAULT NULL,
  `position` varchar(20) DEFAULT NULL,
  `row` int(11) NOT NULL,
  `seat_col` int(11) NOT NULL,
  `is_available` tinyint(1) NOT NULL DEFAULT 1,
  `label` text DEFAULT NULL,
  `seat_type` enum('normal','driver','guide','foldable','wheelchair') NOT NULL DEFAULT 'normal',
  `pair_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `seats`
--

INSERT INTO `seats` (`id`, `vehicle_id`, `seat_number`, `position`, `row`, `seat_col`, `is_available`, `label`, `seat_type`, `pair_id`) VALUES
(1, 1, NULL, NULL, 0, 1, 1, 'Șofer', 'driver', NULL),
(2, 1, NULL, NULL, 0, 4, 1, 'Ghid', 'guide', NULL),
(3, 1, NULL, NULL, 1, 1, 1, '1', 'normal', NULL),
(4, 1, NULL, NULL, 1, 2, 1, '2', 'normal', NULL),
(5, 1, NULL, NULL, 1, 4, 1, '3', 'normal', NULL),
(6, 1, NULL, NULL, 2, 1, 1, '4', 'normal', NULL),
(7, 1, NULL, NULL, 2, 2, 1, '5', 'normal', NULL),
(8, 1, NULL, NULL, 2, 4, 1, '6', 'normal', NULL),
(9, 1, NULL, NULL, 3, 1, 1, '7', 'normal', NULL),
(10, 1, NULL, NULL, 3, 2, 1, '8', 'normal', NULL),
(11, 1, NULL, NULL, 3, 4, 1, '9', 'normal', NULL),
(12, 1, NULL, NULL, 4, 1, 1, '10', 'normal', NULL),
(13, 1, NULL, NULL, 4, 2, 1, '11', 'normal', NULL),
(14, 1, NULL, NULL, 4, 4, 1, '12', 'normal', NULL),
(15, 1, NULL, NULL, 5, 1, 1, '13', 'normal', NULL),
(16, 1, NULL, NULL, 5, 2, 1, '14', 'normal', NULL),
(17, 1, NULL, NULL, 5, 4, 1, '15', 'normal', NULL),
(18, 1, NULL, NULL, 6, 1, 1, '16', 'normal', NULL),
(19, 1, NULL, NULL, 6, 2, 1, '17', 'normal', NULL),
(20, 1, NULL, NULL, 6, 3, 1, '18', 'normal', NULL),
(21, 1, NULL, NULL, 6, 4, 1, '19', 'normal', NULL),
(23, 2, NULL, NULL, 0, 1, 1, 'Șofer', 'driver', NULL),
(24, 2, NULL, NULL, 0, 3, 1, 'Ghid', 'guide', NULL),
(25, 2, NULL, NULL, 1, 1, 1, '1', 'normal', NULL),
(26, 2, NULL, NULL, 1, 2, 1, '2', 'normal', NULL),
(27, 2, NULL, NULL, 1, 4, 1, '3', 'normal', NULL),
(28, 2, NULL, NULL, 2, 1, 1, '4', 'normal', NULL),
(29, 2, NULL, NULL, 2, 2, 1, '5', 'normal', NULL),
(30, 2, NULL, NULL, 2, 4, 1, '6', 'normal', NULL),
(31, 2, NULL, NULL, 3, 1, 1, '7', 'normal', NULL),
(32, 2, NULL, NULL, 3, 2, 1, '8', 'normal', NULL),
(33, 2, NULL, NULL, 3, 4, 1, '9', 'normal', NULL),
(34, 2, NULL, NULL, 4, 1, 1, '10', 'normal', NULL),
(35, 2, NULL, NULL, 4, 2, 1, '11', 'normal', NULL),
(36, 2, NULL, NULL, 4, 4, 1, '12', 'normal', NULL),
(37, 2, NULL, NULL, 5, 1, 1, '13', 'normal', NULL),
(38, 2, NULL, NULL, 5, 2, 1, '14', 'normal', NULL),
(39, 2, NULL, NULL, 5, 4, 1, '15', 'normal', NULL),
(40, 2, NULL, NULL, 6, 1, 1, '16', 'normal', NULL),
(41, 2, NULL, NULL, 6, 2, 1, '17', 'normal', NULL),
(42, 2, NULL, NULL, 6, 3, 1, '18', 'normal', NULL),
(43, 2, NULL, NULL, 6, 4, 1, '19', 'normal', NULL),
(44, 2, NULL, NULL, 0, 4, 1, '20', 'normal', NULL),
(45, 3, NULL, NULL, 0, 1, 1, 'Șofer', 'driver', NULL),
(46, 3, NULL, NULL, 0, 3, 1, 'Ghid', 'guide', NULL),
(47, 3, NULL, NULL, 1, 1, 1, '1', 'normal', NULL),
(48, 3, NULL, NULL, 1, 2, 1, '2', 'normal', NULL),
(49, 3, NULL, NULL, 1, 4, 1, '3', 'normal', NULL),
(50, 3, NULL, NULL, 1, 5, 1, '4', 'normal', NULL),
(51, 3, NULL, NULL, 2, 1, 1, '5', 'normal', NULL),
(52, 3, NULL, NULL, 2, 2, 1, '6', 'normal', NULL),
(53, 3, NULL, NULL, 2, 4, 1, '7', 'normal', NULL),
(54, 3, NULL, NULL, 2, 5, 1, '8', 'normal', NULL),
(55, 3, NULL, NULL, 3, 1, 1, '9', 'normal', NULL),
(56, 3, NULL, NULL, 3, 2, 1, '10', 'normal', NULL),
(57, 3, NULL, NULL, 3, 4, 1, '11', 'normal', NULL),
(58, 3, NULL, NULL, 3, 5, 1, '12', 'normal', NULL),
(59, 3, NULL, NULL, 4, 1, 1, '13', 'normal', NULL),
(60, 3, NULL, NULL, 4, 2, 1, '14', 'normal', NULL),
(61, 3, NULL, NULL, 4, 4, 1, '15', 'normal', NULL),
(62, 3, NULL, NULL, 4, 5, 1, '16', 'normal', NULL),
(63, 3, NULL, NULL, 5, 1, 1, '17', 'normal', NULL),
(64, 3, NULL, NULL, 5, 2, 1, '18', 'normal', NULL),
(65, 3, NULL, NULL, 5, 4, 1, '19', 'normal', NULL),
(66, 3, NULL, NULL, 5, 5, 1, '20', 'normal', NULL),
(67, 3, NULL, NULL, 6, 1, 1, '21', 'normal', NULL),
(68, 3, NULL, NULL, 6, 2, 1, '22', 'normal', NULL),
(69, 3, NULL, NULL, 6, 4, 1, '23', 'normal', NULL),
(70, 3, NULL, NULL, 6, 5, 1, '24', 'normal', NULL),
(71, 3, NULL, NULL, 7, 1, 1, '25', 'normal', NULL),
(72, 3, NULL, NULL, 7, 2, 1, '26', 'normal', NULL),
(73, 3, NULL, NULL, 8, 1, 1, '27', 'normal', NULL),
(74, 3, NULL, NULL, 8, 2, 1, '28', 'normal', NULL),
(75, 3, NULL, NULL, 8, 4, 1, '29', 'normal', NULL),
(76, 3, NULL, NULL, 8, 5, 1, '30', 'normal', NULL),
(77, 3, NULL, NULL, 9, 1, 1, '31', 'normal', NULL),
(78, 3, NULL, NULL, 9, 2, 1, '32', 'normal', NULL),
(79, 3, NULL, NULL, 9, 4, 1, '33', 'normal', NULL),
(80, 3, NULL, NULL, 9, 5, 1, '34', 'normal', NULL),
(81, 3, NULL, NULL, 10, 1, 1, '35', 'normal', NULL),
(82, 3, NULL, NULL, 10, 2, 1, '36', 'normal', NULL),
(83, 3, NULL, NULL, 10, 4, 1, '37', 'normal', NULL),
(84, 3, NULL, NULL, 10, 5, 1, '38', 'normal', NULL),
(85, 3, NULL, NULL, 11, 1, 1, '39', 'normal', NULL),
(86, 3, NULL, NULL, 11, 2, 1, '40', 'normal', NULL),
(87, 3, NULL, NULL, 11, 4, 1, '41', 'normal', NULL),
(88, 3, NULL, NULL, 11, 5, 1, '42', 'normal', NULL),
(89, 3, NULL, NULL, 12, 1, 1, '43', 'normal', NULL),
(90, 3, NULL, NULL, 12, 2, 1, '44', 'normal', NULL),
(91, 3, NULL, NULL, 12, 4, 1, '45', 'normal', NULL),
(92, 3, NULL, NULL, 12, 5, 1, '46', 'normal', NULL),
(93, 3, NULL, NULL, 13, 1, 1, '47', 'normal', NULL),
(94, 3, NULL, NULL, 13, 2, 1, '48', 'normal', NULL),
(95, 3, NULL, NULL, 13, 4, 1, '49', 'normal', NULL),
(96, 3, NULL, NULL, 13, 5, 1, '50', 'normal', NULL),
(98, 4, NULL, NULL, 0, 1, 1, 'Șofer', 'driver', NULL),
(99, 4, NULL, NULL, 0, 3, 1, 'Ghid', 'guide', NULL),
(100, 4, NULL, NULL, 1, 1, 1, '1', 'normal', NULL),
(101, 4, NULL, NULL, 1, 2, 1, '2', 'normal', NULL),
(102, 4, NULL, NULL, 1, 4, 1, '3', 'normal', NULL),
(103, 4, NULL, NULL, 1, 5, 1, '4', 'normal', NULL),
(104, 4, NULL, NULL, 2, 1, 1, '5', 'normal', NULL),
(105, 4, NULL, NULL, 2, 2, 1, '6', 'normal', NULL),
(106, 4, NULL, NULL, 2, 4, 1, '7', 'normal', NULL),
(107, 4, NULL, NULL, 2, 5, 1, '8', 'normal', NULL),
(108, 4, NULL, NULL, 3, 1, 1, '9', 'normal', NULL),
(109, 4, NULL, NULL, 3, 2, 1, '10', 'normal', NULL),
(110, 4, NULL, NULL, 3, 4, 1, '11', 'normal', NULL),
(111, 4, NULL, NULL, 3, 5, 1, '12', 'normal', NULL),
(112, 4, NULL, NULL, 4, 1, 1, '13', 'normal', NULL),
(113, 4, NULL, NULL, 4, 2, 1, '14', 'normal', NULL),
(114, 4, NULL, NULL, 4, 4, 1, '15', 'normal', NULL),
(115, 4, NULL, NULL, 4, 5, 1, '16', 'normal', NULL),
(116, 4, NULL, NULL, 5, 1, 1, '17', 'normal', NULL),
(117, 4, NULL, NULL, 5, 2, 1, '18', 'normal', NULL),
(118, 4, NULL, NULL, 5, 4, 1, '19', 'normal', NULL),
(119, 4, NULL, NULL, 5, 5, 1, '20', 'normal', NULL),
(120, 4, NULL, NULL, 6, 1, 1, '21', 'normal', NULL),
(121, 4, NULL, NULL, 6, 2, 1, '22', 'normal', NULL),
(122, 4, NULL, NULL, 6, 4, 1, '23', 'normal', NULL),
(123, 4, NULL, NULL, 6, 5, 1, '24', 'normal', NULL),
(124, 4, NULL, NULL, 7, 1, 1, '25', 'normal', NULL),
(125, 4, NULL, NULL, 7, 2, 1, '26', 'normal', NULL),
(126, 4, NULL, NULL, 7, 4, 1, '27', 'normal', NULL),
(127, 4, NULL, NULL, 7, 5, 1, '28', 'normal', NULL),
(128, 4, NULL, NULL, 8, 1, 1, '29', 'normal', NULL),
(129, 4, NULL, NULL, 8, 2, 1, '30', 'normal', NULL),
(130, 4, NULL, NULL, 8, 4, 1, '31', 'normal', NULL),
(131, 4, NULL, NULL, 8, 5, 1, '32', 'normal', NULL),
(132, 4, NULL, NULL, 9, 1, 1, '33', 'normal', NULL),
(133, 4, NULL, NULL, 9, 2, 1, '34', 'normal', NULL),
(134, 4, NULL, NULL, 9, 4, 1, '35', 'normal', NULL),
(135, 4, NULL, NULL, 9, 5, 1, '36', 'normal', NULL),
(136, 4, NULL, NULL, 10, 1, 1, '37', 'normal', NULL),
(137, 4, NULL, NULL, 10, 2, 1, '38', 'normal', NULL),
(138, 4, NULL, NULL, 10, 4, 1, '39', 'normal', NULL),
(139, 4, NULL, NULL, 10, 5, 1, '40', 'normal', NULL),
(140, 4, NULL, NULL, 11, 1, 1, '41', 'normal', NULL),
(141, 4, NULL, NULL, 11, 2, 1, '42', 'normal', NULL),
(142, 4, NULL, NULL, 11, 4, 1, '43', 'normal', NULL),
(143, 4, NULL, NULL, 11, 5, 1, '44', 'normal', NULL),
(144, 4, NULL, NULL, 12, 1, 1, '45', 'normal', NULL),
(145, 4, NULL, NULL, 12, 2, 1, '46', 'normal', NULL),
(146, 4, NULL, NULL, 12, 4, 1, '47', 'normal', NULL),
(147, 4, NULL, NULL, 12, 5, 1, '48', 'normal', NULL),
(148, 4, NULL, NULL, 13, 1, 1, '49', 'normal', NULL),
(149, 4, NULL, NULL, 13, 2, 1, '50', 'normal', NULL),
(150, 4, NULL, NULL, 13, 4, 1, '51', 'normal', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `seat_locks`
--

CREATE TABLE `seat_locks` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `trip_id` bigint(20) UNSIGNED NOT NULL,
  `seat_id` bigint(20) UNSIGNED NOT NULL,
  `board_station_id` bigint(20) UNSIGNED NOT NULL,
  `exit_station_id` bigint(20) UNSIGNED NOT NULL,
  `operator_id` bigint(20) UNSIGNED DEFAULT NULL,
  `employee_id` bigint(20) UNSIGNED DEFAULT NULL,
  `hold_token` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `seat_locks`
--

INSERT INTO `seat_locks` (`id`, `trip_id`, `seat_id`, `board_station_id`, `exit_station_id`, `operator_id`, `employee_id`, `hold_token`, `created_at`, `expires_at`) VALUES
(261, 1748, 4, 1, 2, 2, 1, 'd000961b-a8ee-4a78-bbcd-503c5446b155', '2025-10-27 19:40:29', '2025-10-27 19:41:14'),
(262, 1748, 4, 1, 2, 2, 1, '4d0faba1-4053-4466-bebf-c4a7f6a0ce2f', '2025-10-27 19:40:29', '2025-10-27 19:41:14'),
(264, 1735, 3, 2, 1, 2, 1, '0c39b54d-934c-4163-ad91-1800658ea940', '2025-10-27 19:40:34', '2025-10-27 19:41:19'),
(266, 1748, 4, 1, 2, 2, 1, '3feaed94-15f1-4f34-bd7a-50e2c7591d38', '2025-10-27 19:40:47', '2025-10-27 19:41:32'),
(267, 1748, 4, 1, 2, 2, 1, 'ccefc817-86e5-435e-937c-cab765f31e25', '2025-10-27 19:40:47', '2025-10-27 19:41:32'),
(269, 1748, 7, 1, 2, 2, 1, '1b5529be-c21b-4aab-b88d-e08fd175f1ab', '2025-10-27 19:40:50', '2025-10-27 19:41:35'),
(270, 1748, 6, 1, 2, 2, 1, '05f2c76c-7ea9-454b-ab7f-1f9cc5f4c775', '2025-10-27 19:40:50', '2025-10-27 19:41:35'),
(295, 1748, 20, 1, 2, 2, 1, '9fca3e50-1a2a-4b4f-aff1-594d8d583807', '2025-10-27 19:40:52', '2025-10-27 19:41:37'),
(297, 1748, 6, 1, 2, 2, 1, '5e69a276-1572-4d26-9323-32176aabc8b1', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(298, 1748, 7, 1, 2, 2, 1, '33728ba9-4f7a-4641-a5da-24eabfee233e', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(299, 1748, 9, 1, 2, 2, 1, 'afe5e27a-3462-40c9-a689-cfcc0f4ea3e6', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(300, 1748, 10, 1, 2, 2, 1, '4a301c11-62f1-4677-8e82-0c245101fcc3', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(301, 1748, 6, 1, 2, 2, 1, '67ce0a27-f0d1-4e08-9f2c-2e16f76e5fbe', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(302, 1748, 7, 1, 2, 2, 1, '0b0672a4-c6bb-4b89-bcc9-22855e42ade9', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(303, 1748, 9, 1, 2, 2, 1, 'c160972d-fd1a-45a9-9239-a9226197ca58', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(304, 1748, 10, 1, 2, 2, 1, '39ad5296-cf8c-4dda-a262-9c47d944d258', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(305, 1748, 6, 1, 2, 2, 1, '2bf2c4a6-5937-49b6-bc41-fc1a2fd4824f', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(306, 1748, 7, 1, 2, 2, 1, '07e83a97-d6f0-4944-b03d-8985b4caeeaa', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(307, 1748, 9, 1, 2, 2, 1, 'bac63969-8e1a-4390-8ba8-96e78762558f', '2025-10-27 19:40:53', '2025-10-27 19:41:38'),
(308, 1748, 10, 1, 2, 2, 1, '20e62282-415b-4d6f-8386-e0a1f0c3adb6', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(309, 1748, 6, 1, 2, 2, 1, '5bd78063-e0fb-4a64-ab24-d6ce86977b4f', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(310, 1748, 7, 1, 2, 2, 1, '68c831d8-86d2-4fff-b349-cd7558f59e25', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(311, 1748, 9, 1, 2, 2, 1, 'dda62386-8286-4ac7-8368-c34884191279', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(312, 1748, 10, 1, 2, 2, 1, '7260b9bc-6119-4a43-84b7-1e339e18eac8', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(313, 1748, 6, 1, 2, 2, 1, '634b7ea2-c3fc-48ae-a15a-960c82bbbf1c', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(314, 1748, 7, 1, 2, 2, 1, '3ebae901-9939-48b5-aaaa-9a0426bce14c', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(315, 1748, 9, 1, 2, 2, 1, '168e23ea-79cd-457b-833c-9889eb6a6df6', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(316, 1748, 10, 1, 2, 2, 1, '2184d684-6d07-4bd1-91cb-1bae1b48eddc', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(317, 1748, 6, 1, 2, 2, 1, 'bce82632-aa28-4063-bca0-6bfe1ab73a25', '2025-10-27 19:40:54', '2025-10-27 19:41:39'),
(318, 1748, 7, 1, 2, 2, 1, '9b3ad52d-f247-4ce5-88c3-8ae04a90e268', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(319, 1748, 9, 1, 2, 2, 1, 'f3c3ada8-7a09-45c0-a335-c0eed4201949', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(320, 1748, 10, 1, 2, 2, 1, '8982d87a-d1f9-462b-893b-6395e8902f05', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(321, 1748, 4, 1, 2, 2, 1, '4c924a0a-492a-46f4-b681-cda56b490cea', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(322, 1748, 6, 1, 2, 2, 1, 'de873bfa-6641-4ca0-8c72-bda37a94898f', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(323, 1748, 7, 1, 2, 2, 1, '8cd60009-3205-4eb7-aaa3-3ad73cd0901f', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(324, 1748, 9, 1, 2, 2, 1, '9f137ff9-fef1-4b8a-bdf4-004a82d4667d', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(325, 1748, 10, 1, 2, 2, 1, '80279edc-8038-4345-a5c8-4076a22b38e5', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(326, 1748, 4, 1, 2, 2, 1, '226b179e-f5de-4612-827f-fb67c112b6b3', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(327, 1748, 6, 1, 2, 2, 1, 'b7f43183-293f-4fa9-8420-172a7dcae837', '2025-10-27 19:40:55', '2025-10-27 19:41:40'),
(328, 1748, 7, 1, 2, 2, 1, '2a57084d-6370-491d-a04f-f5fb2e815135', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(329, 1748, 9, 1, 2, 2, 1, '76d88c39-59c9-48d1-b063-4d84a00a2036', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(330, 1748, 10, 1, 2, 2, 1, '5517f2cf-461e-4d58-afec-e975cd40c8f9', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(331, 1748, 4, 1, 2, 2, 1, '4e02bf4d-4065-4848-833e-864245111aa3', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(332, 1748, 6, 1, 2, 2, 1, '1c495678-1653-4593-930f-62fa2f29cf84', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(333, 1748, 9, 1, 2, 2, 1, '852b0a18-0610-4a5b-8d41-115bc2a11efb', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(334, 1748, 7, 1, 2, 2, 1, '9ece972b-4987-4905-9a09-62e42bff91b4', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(335, 1748, 10, 1, 2, 2, 1, '6a230b90-d329-4c76-9e1f-ce25cbc80f70', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(336, 1748, 4, 1, 2, 2, 1, 'ee6be8f8-1c62-45b0-8617-3e83827bd7cf', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(337, 1748, 6, 1, 2, 2, 1, '7abde9b8-e0b7-40d6-9c38-144b754d3aa6', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(338, 1748, 7, 1, 2, 2, 1, '56a06a4d-70c4-4985-a925-9bbc6c4f81dd', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(339, 1748, 9, 1, 2, 2, 1, '66b9e30d-e26c-4312-a544-d38108aa1e2e', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(340, 1748, 10, 1, 2, 2, 1, '4bd2edf4-88a8-4140-9001-2bfae36bf720', '2025-10-27 19:40:56', '2025-10-27 19:41:41'),
(341, 1748, 4, 1, 2, 2, 1, '21b58873-c05e-4a04-93c3-8922513c7ec2', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(342, 1748, 6, 1, 2, 2, 1, '060fa7c0-1dc4-444d-b536-42583a8b42bb', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(343, 1748, 7, 1, 2, 2, 1, '20cc8f65-827d-4c63-b856-4fdab3ad6eb8', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(344, 1748, 9, 1, 2, 2, 1, 'dafb92a9-4ab2-4866-9ac4-db36c795f97d', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(345, 1748, 10, 1, 2, 2, 1, '69e0dd47-7f2c-4087-96c4-a26cfed3f272', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(346, 1748, 4, 1, 2, 2, 1, 'ce921f7f-0966-4d38-b368-e528dd46d9b1', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(347, 1748, 6, 1, 2, 2, 1, '048377d6-2f02-4205-ad26-5a8d91bc8991', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(348, 1748, 7, 1, 2, 2, 1, '7f252b8b-721d-4f37-bad3-120e21775154', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(349, 1748, 9, 1, 2, 2, 1, '4fd08925-1bfc-4e55-a9cd-cf8282c96b29', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(350, 1748, 10, 1, 2, 2, 1, '002f97b9-c234-4bcb-b1a1-c2a6f78138bd', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(351, 1748, 4, 1, 2, 2, 1, '17bc7808-f747-4a9e-86f3-493308c0f143', '2025-10-27 19:40:57', '2025-10-27 19:41:42'),
(352, 1748, 6, 1, 2, 2, 1, 'dd4812c2-278c-46e9-a6d9-64303357d314', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(353, 1748, 7, 1, 2, 2, 1, '2ab84971-987d-47a0-b526-1dd721acbbc7', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(354, 1748, 9, 1, 2, 2, 1, 'ff058a3a-838b-4aa5-a328-c046a2555ef3', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(355, 1748, 10, 1, 2, 2, 1, '8767e96d-85d7-4d05-8190-019b24a1309f', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(356, 1748, 4, 1, 2, 2, 1, '12e7db46-95a9-4f65-a95d-ed11d00007df', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(357, 1748, 6, 1, 2, 2, 1, '8b03050a-60cf-4ce3-b95c-00fcaa5bd061', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(358, 1748, 7, 1, 2, 2, 1, 'f09108f1-af8d-4b23-a523-ac30c3fbb8bd', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(359, 1748, 9, 1, 2, 2, 1, '988e5d56-5617-48a2-811c-0f1bd023dd8b', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(360, 1748, 10, 1, 2, 2, 1, '61bf2756-2b54-4ccb-aa57-0786771a956a', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(361, 1748, 4, 1, 2, 2, 1, '9b1fff4b-6151-4247-82ce-025d5779cd20', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(362, 1748, 6, 1, 2, 2, 1, '1b9b9785-e1c9-4f35-92c7-db122ad1b1fb', '2025-10-27 19:40:58', '2025-10-27 19:41:43'),
(363, 1748, 7, 1, 2, 2, 1, '602e92f9-acab-4484-bfe6-03f38ad4f220', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(364, 1748, 9, 1, 2, 2, 1, '9d714238-32aa-4614-890a-887e35c79c19', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(365, 1748, 10, 1, 2, 2, 1, '87d5f25d-5623-42ca-bc76-af8b25d7e521', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(366, 1748, 4, 1, 2, 2, 1, '9efd7de7-1314-472a-b3dc-c92c66fc41c5', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(367, 1748, 7, 1, 2, 2, 1, 'c948cc00-178d-4095-b6d6-9b6929bc6838', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(368, 1748, 9, 1, 2, 2, 1, '26f90134-3e86-476b-b14e-8aae99a71336', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(369, 1748, 6, 1, 2, 2, 1, '1660e3a9-cfbf-41c9-9f62-f8c9a2f5dc41', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(370, 1748, 10, 1, 2, 2, 1, 'e24ff721-d643-4c9c-8441-05d3e008d73f', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(371, 1748, 4, 1, 2, 2, 1, 'd3c1348c-99c7-437e-936c-b509a2c7c25a', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(372, 1748, 6, 1, 2, 2, 1, '156f216e-b982-407b-ac83-01f2b8aa5325', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(373, 1748, 7, 1, 2, 2, 1, '4a026f1a-ee19-4890-af30-82c78cab7e0e', '2025-10-27 19:40:59', '2025-10-27 19:41:44'),
(374, 1748, 9, 1, 2, 2, 1, '94348ea8-73aa-442a-b3d8-70e95f47e5c6', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(375, 1748, 10, 1, 2, 2, 1, '2a9fa283-f279-4bc6-862d-42626e1cd33d', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(376, 1748, 4, 1, 2, 2, 1, '1de63c7a-1521-41dd-bafd-9f3e1c3dade9', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(377, 1748, 6, 1, 2, 2, 1, 'f2568c7b-b38d-4789-8541-107f59fad884', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(378, 1748, 7, 1, 2, 2, 1, '56a44548-4d7d-449f-a4a7-1eb68c701778', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(379, 1748, 9, 1, 2, 2, 1, 'e5add502-1d91-4abc-b681-fe0422664db7', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(380, 1748, 10, 1, 2, 2, 1, '12ce0202-6586-4fa2-9dee-52c07d92fc6d', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(381, 1748, 4, 1, 2, 2, 1, '8c422659-0601-4008-8d45-e48c37082312', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(382, 1748, 6, 1, 2, 2, 1, 'b688c5c7-f619-46f7-aac8-8a976af570b3', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(383, 1748, 7, 1, 2, 2, 1, 'ab651ff4-678b-4115-9a69-561a4cadbf07', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(384, 1748, 9, 1, 2, 2, 1, '3799b848-ce5f-4df5-aec1-d783c58bf183', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(385, 1748, 10, 1, 2, 2, 1, 'ca1dfd86-90ba-4300-9959-41b137c269f2', '2025-10-27 19:41:00', '2025-10-27 19:41:45'),
(386, 1748, 4, 1, 2, 2, 1, '39d7c970-1f3e-4a8c-8f19-f059aa318b8e', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(387, 1748, 6, 1, 2, 2, 1, '1ebb65e2-e685-4634-9db5-c25536655a29', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(388, 1748, 7, 1, 2, 2, 1, 'f868fd1b-c45f-4e70-9678-bcd6a666a157', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(389, 1748, 9, 1, 2, 2, 1, 'ef0deae1-722e-4d95-956b-ac66240040b5', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(390, 1748, 10, 1, 2, 2, 1, '7626e9e6-25da-439a-95b9-e14131b49abe', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(391, 1748, 6, 1, 2, 2, 1, '6ccb06df-ba7c-4210-a978-cf264f11f98d', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(392, 1748, 4, 1, 2, 2, 1, 'f8071235-2aa2-44be-94f3-f1c90b80bf34', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(393, 1748, 7, 1, 2, 2, 1, '9aa26a80-8967-453b-a8df-f86333bf5d26', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(394, 1748, 9, 1, 2, 2, 1, '3b3079c6-c8d5-460a-8602-cc862931f94f', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(395, 1748, 10, 1, 2, 2, 1, 'ed160c55-5ce1-4d80-81ca-a03a44b0df38', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(396, 1748, 4, 1, 2, 2, 1, 'e7f39fd5-8270-40f4-8b22-bf9ddf737478', '2025-10-27 19:41:01', '2025-10-27 19:41:46'),
(397, 1748, 7, 1, 2, 2, 1, '6115a68f-b3bb-4092-a59a-f53ed9c363ac', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(398, 1748, 6, 1, 2, 2, 1, 'b3e76a62-f85e-4a9d-9dce-0ca4b276d1f1', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(399, 1748, 9, 1, 2, 2, 1, '5d391ed2-72ea-457b-abe4-5242a2f8e085', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(400, 1748, 10, 1, 2, 2, 1, 'b3e57fd3-8cfe-4605-b1b3-da55652c4570', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(401, 1748, 4, 1, 2, 2, 1, '7d9be3f7-c825-43a8-af9b-26508419332f', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(402, 1748, 6, 1, 2, 2, 1, 'a39aa352-a7d9-4eb5-88c2-05771c45e4dd', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(403, 1748, 7, 1, 2, 2, 1, 'cfae5a56-cc18-4601-93e7-837c2fdf1c63', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(404, 1748, 9, 1, 2, 2, 1, '8dcc4830-2078-4b0c-84a8-ea8ba5516828', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(405, 1748, 10, 1, 2, 2, 1, '0e6029d1-dec2-48d0-ba86-c99438cb4218', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(406, 1748, 4, 1, 2, 2, 1, '14e8bdc6-2a5a-45ce-af9b-2d3aa3caecc2', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(407, 1748, 6, 1, 2, 2, 1, '6adbd893-be82-46f2-9a3b-5de858477520', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(408, 1748, 7, 1, 2, 2, 1, 'afe75eb5-c5e9-442d-87db-e43e8edfcb53', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(409, 1748, 9, 1, 2, 2, 1, '2d05b715-0e1e-4154-aeb8-55cfc1f81385', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(410, 1748, 10, 1, 2, 2, 1, '9c80c1d7-96bf-4bbc-b690-66c22e17cf33', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(411, 1748, 4, 1, 2, 2, 1, '0a81e3cd-9acc-485e-8d27-a9596093c65b', '2025-10-27 19:41:02', '2025-10-27 19:41:47'),
(412, 1748, 6, 1, 2, 2, 1, '49852e70-b744-47ec-8ced-b217efd8a15b', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(413, 1748, 7, 1, 2, 2, 1, 'b5a4e440-5437-446b-9ff4-721f77ba626d', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(414, 1748, 9, 1, 2, 2, 1, '39ea0103-b5ca-4f30-89b0-76d5957a1596', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(415, 1748, 10, 1, 2, 2, 1, 'a2b7de1f-3a90-4980-9848-313e1c118068', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(416, 1748, 4, 1, 2, 2, 1, '747c3f57-2939-420f-b116-a1167398d34e', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(417, 1748, 6, 1, 2, 2, 1, 'dfb1db8d-6251-4e99-bafe-ed2d2c75c6e9', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(418, 1748, 7, 1, 2, 2, 1, '0549b67a-3167-4797-9f96-0902df63acd2', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(419, 1748, 10, 1, 2, 2, 1, '5e50260f-902a-43d7-b014-8894374243dd', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(420, 1748, 4, 1, 2, 2, 1, 'fabb9de1-0ab6-426a-a510-d97d8f4b3f3d', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(421, 1748, 9, 1, 2, 2, 1, '39e57db8-e854-4fe5-ac70-93720b0e9e70', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(422, 1748, 6, 1, 2, 2, 1, '14fc1aa5-76ce-4069-824e-532ea254b23d', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(423, 1748, 7, 1, 2, 2, 1, '5c984aef-dc74-4fb5-88ed-66cac4d58566', '2025-10-27 19:41:03', '2025-10-27 19:41:48'),
(424, 1748, 9, 1, 2, 2, 1, 'fd74997e-34f4-488a-a6d4-f72e1ef5fb74', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(425, 1748, 10, 1, 2, 2, 1, '7b56ad77-f563-4dc1-b22c-7381bdf9ec43', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(426, 1748, 4, 1, 2, 2, 1, '67f76f67-e9b4-4040-808d-9d655be268ba', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(427, 1748, 6, 1, 2, 2, 1, 'a8ed5576-a20d-4ceb-a18f-a5af43ed994c', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(428, 1748, 7, 1, 2, 2, 1, '3f354cc1-3d2c-4059-88f9-43b456360b95', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(429, 1748, 9, 1, 2, 2, 1, '4b8d990b-979c-4eb6-a0ba-f2136e5da555', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(430, 1748, 10, 1, 2, 2, 1, '6c2ee3c8-9326-488a-a614-70dccdbf331a', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(431, 1748, 4, 1, 2, 2, 1, 'd432a01a-c675-4c19-9af3-dec8b0e8ff25', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(432, 1748, 6, 1, 2, 2, 1, '6468bd9e-c1a7-4d66-8b26-9a0adaa649af', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(433, 1748, 7, 1, 2, 2, 1, 'ddaf3331-cdba-4ea2-9556-945310dcac23', '2025-10-27 19:41:04', '2025-10-27 19:41:49'),
(434, 1748, 10, 1, 2, 2, 1, 'c8eea040-887d-44b7-aa40-253c335dbffc', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(435, 1748, 4, 1, 2, 2, 1, '061e01f1-9cd9-4a69-baef-2aa93aba673b', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(436, 1748, 9, 1, 2, 2, 1, 'e9764f6f-e6e3-4583-a415-d2756057df80', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(437, 1748, 6, 1, 2, 2, 1, '08c1f2d7-287d-4284-bca5-81d3b9ad958c', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(438, 1748, 7, 1, 2, 2, 1, '4d1a38b4-fc6f-4d89-bd54-3bd37da4ff08', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(439, 1748, 10, 1, 2, 2, 1, '071a6b03-b201-45c5-aed9-01ac8930ee06', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(440, 1748, 9, 1, 2, 2, 1, 'de6883f5-6979-4c3f-be02-1a66d3057c6e', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(441, 1748, 4, 1, 2, 2, 1, '713623f7-7c36-4055-aed7-270dfe5b7d5d', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(442, 1748, 7, 1, 2, 2, 1, '245a3a8c-35c0-4d2f-a4e7-e1c1059e8eec', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(443, 1748, 9, 1, 2, 2, 1, 'd5e683b2-3a82-4118-911e-1f6b922faf3a', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(444, 1748, 6, 1, 2, 2, 1, '92f648dc-f0ac-476b-823a-5508cb90c0cb', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(445, 1748, 10, 1, 2, 2, 1, 'cfa86578-d813-4e79-96b2-5802419ceb50', '2025-10-27 19:41:05', '2025-10-27 19:41:50'),
(446, 1748, 6, 1, 2, 2, 1, '3a8fbc7a-8b38-42da-ae19-faacd4ae8a31', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(447, 1748, 9, 1, 2, 2, 1, '6bf43c51-3a3e-4c14-afd3-b6ceb6326410', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(448, 1748, 7, 1, 2, 2, 1, 'f59ce2e7-369c-44bc-8cab-3b97ea95ddb3', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(449, 1748, 4, 1, 2, 2, 1, '36021e4e-b543-448d-a50e-4c2cba4e04a7', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(450, 1748, 4, 1, 2, 2, 1, 'ac44c70d-4d67-4382-ad32-5c5ecc350019', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(451, 1748, 6, 1, 2, 2, 1, 'cc4fdf4b-48a4-4fa7-ad64-86a4ecb986ec', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(452, 1748, 10, 1, 2, 2, 1, '517c314e-473d-4741-9bed-d71883086a23', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(453, 1748, 7, 1, 2, 2, 1, 'dec8aee6-c496-485b-8a14-81f0c4f2412c', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(454, 1748, 9, 1, 2, 2, 1, '9fc96f7b-f34e-437f-a70b-49476c5eec41', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(455, 1748, 10, 1, 2, 2, 1, '1e1e7cd6-2048-4abf-b346-ae28e36f0758', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(456, 1748, 4, 1, 2, 2, 1, 'bcb07e85-49ac-40fe-aff7-a3f0c21d1352', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(457, 1748, 9, 1, 2, 2, 1, 'd6805dcc-2b38-4a55-95bf-880114a14f7d', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(458, 1748, 7, 1, 2, 2, 1, '7ba28ae5-3103-48cd-9681-1be84fb42c38', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(459, 1748, 10, 1, 2, 2, 1, '2cded42b-4c2a-4374-b0ed-1982caeaff9d', '2025-10-27 19:41:06', '2025-10-27 19:41:51'),
(460, 1748, 4, 1, 2, 2, 1, '16d5c59a-8555-41a7-86a0-66e378dadfd3', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(461, 1748, 9, 1, 2, 2, 1, '80de5ea6-ed51-4485-a743-038ca4a3cbf4', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(462, 1748, 4, 1, 2, 2, 1, 'c93fcf0d-7702-407e-a2aa-2450eecc4cc0', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(463, 1748, 10, 1, 2, 2, 1, '757b3985-b28f-45cd-811a-6d61f3adb1c9', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(464, 1748, 4, 1, 2, 2, 1, '9caaffc9-bad4-473f-adac-9233499883b8', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(465, 1748, 4, 1, 2, 2, 1, '37b84fa4-3d1a-4033-b415-fbc79abf6db9', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(466, 1748, 4, 1, 2, 2, 1, '412f855f-ed9d-45ea-aaa1-1274c49cd6c6', '2025-10-27 19:41:07', '2025-10-27 19:41:52'),
(467, 1748, 4, 1, 2, 2, 1, 'f089f708-2892-4e01-814b-29e0b52e88e3', '2025-10-27 19:41:10', '2025-10-27 19:41:55'),
(468, 1748, 4, 1, 2, 2, 1, '6699a38a-7e10-4cbf-b73d-b9932ab8fe68', '2025-10-27 19:41:10', '2025-10-27 19:41:55'),
(469, 1748, 4, 1, 2, 2, 1, '392abe1a-bdd2-4f8b-a9d2-b3337b87e1c1', '2025-10-27 19:41:10', '2025-10-27 19:41:55');

-- --------------------------------------------------------

--
-- Table structure for table `sessions`
--

CREATE TABLE `sessions` (
  `id` int(11) NOT NULL,
  `employee_id` int(11) NOT NULL,
  `token_hash` varchar(255) NOT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `revoked_at` datetime DEFAULT NULL,
  `rotated_from` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `sessions`
--

INSERT INTO `sessions` (`id`, `employee_id`, `token_hash`, `user_agent`, `ip`, `created_at`, `expires_at`, `revoked_at`, `rotated_from`) VALUES
(1, 1, '1900b4d2ec67321f82faadb7310b19ecbd905a25abcfeda84f7afb5796150ba7', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '82.77.242.74', '2025-10-24 15:54:30', '2025-11-23 15:54:30', NULL, NULL),
(2, 2, '94d49d8820a860fae8fd0cc610dde19fb86b2870c3c3f0d6ff0f7c5a9f45fb64', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', '82.77.242.74', '2025-10-24 16:16:04', '2025-11-23 16:16:04', NULL, NULL),
(3, 1, 'fb896de887c23d74aca60bd009bf6c6dae26ae791a80293a8ce203df17bb2481', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '90.95.138.11', '2025-10-26 21:41:10', '2025-11-25 21:41:10', NULL, NULL),
(4, 1, '79b90c0cd6ca4a23ab307db4a68dbb61e7a4d34935dea75078c5545fb46ee16e', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-27 09:57:02', '2025-11-26 09:57:02', '2025-10-27 15:42:08', NULL),
(5, 3, '29392a498eac86fd8ed4ce77b05dacce93c8f4cb18826ba9d7ace325b3108fc1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-27 15:43:15', '2025-11-26 15:43:15', '2025-10-27 15:50:37', NULL),
(6, 3, '6c4ed31a0d13eec02052b66c64a5a45bea7794017d1113b4bfab0613c975a1da', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-27 15:50:38', '2025-11-26 15:50:38', '2025-10-27 18:03:56', NULL),
(7, 3, '20c9d0191372cfde57e00a5bf4a2d6efc95161f3006355e61dafdf2e8a7a83b4', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-27 18:03:36', '2025-11-26 18:03:36', NULL, NULL),
(8, 1, 'fac45fc050fbc39b712ffce1612f84df178c5267ee07f69eae8f9f0a83955faf', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-27 18:03:59', '2025-11-26 18:03:59', NULL, NULL),
(9, 1, 'ca744c078491c4e16db0854ae5b3695afb0001d9ee53313df3f10cabc12cb142', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 08:49:18', '2025-11-27 08:49:18', NULL, NULL),
(10, 1, 'ac19692a458b06a07338998f50670fbb31ad899bcde4396c9c46602661671800', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 10:51:43', '2025-11-27 10:51:43', NULL, NULL),
(11, 3, 'c0fa925bbd3bd471afc90520f9b121922b2ea4c8b77d28d5d6fedc06660a0a00', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 12:46:39', '2025-11-27 12:46:39', NULL, NULL),
(12, 2, 'fcab645b34b38c275672ba99d8cb413c4e31728cac7cc4b510371e83f6f476b7', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', '127.0.0.1', '2025-10-28 12:57:07', '2025-11-27 12:57:07', NULL, NULL),
(13, 3, '80c0fcc0792d14095b8a077c1515597ebbf1aa0fc17f365c4159c897039fd8fa', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 13:18:16', '2025-11-27 13:18:16', NULL, NULL),
(14, 3, '86bd900fc3a4bf368de49ec506cf633ecb27bfb207d9a3d23c7c2c76b5921fa2', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 14:20:03', '2025-11-27 14:20:03', NULL, NULL),
(15, 3, '2aaff7430230f3af3a31b6be5ddf446cc29482396be2c2491ab461bdc37ebf89', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 15:36:51', '2025-11-27 15:36:51', NULL, NULL),
(16, 3, '5b227b4114c6fa9492677f4a3503a61bec28877837397f0264c3b520846d2fb3', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 16:47:31', '2025-11-27 16:47:31', NULL, NULL),
(17, 5, '5b5d48f8bfc185a19f9b56804ad64bc1f962cd4b0b45e25df77feb81462dac2c', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 18:50:01', '2025-11-27 18:50:01', '2025-10-28 18:50:18', NULL),
(18, 5, '57c199b85505c80283e070341d605121d51a3c893bb65627e5acbc4de4a8f46b', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 18:50:19', '2025-11-27 18:50:19', '2025-10-28 18:50:29', NULL),
(19, 1, '460b99f5daaaeebefbac3a69e5710d1b2df571d3d2a57c99f8b4db2cd0fc4b0e', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 18:50:32', '2025-11-27 18:50:32', NULL, NULL),
(20, 1, '15401d1d2f14c940242455dbab3767a050670c5f8414f54e85083e6c770edc58', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-28 20:09:29', '2025-11-27 20:09:29', NULL, NULL),
(21, 1, '3b866014c16c93c24ed1e518e909f93880296a1dbb2d0793edc49e8f94beebd4', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-29 16:17:06', '2025-11-28 16:17:06', '2025-10-29 16:25:45', NULL),
(22, 1, 'dc1af5a93d22d94bb9329ea21f1229a2b5b8aa39fb6d62e8c5a4bc20b47b889f', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-29 16:25:47', '2025-11-28 16:25:47', NULL, NULL),
(23, 3, '3262e849712c36a64d1fddb34cc67e36a537512b042c2394599d2521e272857d', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-29 16:35:19', '2025-11-28 16:35:19', NULL, NULL),
(24, 1, '4bb3f11cf16b2dc58545bda2dd92e61ee9b37dbdc38905ebd47169476dd63ae1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0', '127.0.0.1', '2025-10-30 12:49:11', '2025-11-29 12:49:11', NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `stations`
--

CREATE TABLE `stations` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `locality` text DEFAULT NULL,
  `county` text DEFAULT NULL,
  `latitude` decimal(11,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `stations`
--

INSERT INTO `stations` (`id`, `name`, `locality`, `county`, `latitude`, `longitude`, `created_at`, `updated_at`) VALUES
(1, 'Botoșani', 'Botoșani', 'Botoșani', 47.74392031, 26.66256300, '2025-10-24 16:11:41', '2025-10-28 17:06:26'),
(2, 'Iași', 'Iași', 'Iași', -0.00102997, -0.03227234, '2025-10-24 16:11:56', '2025-10-24 16:11:56'),
(3, 'Harlau', 'Harlau', 'Iasi', -0.00446320, 0.00823975, '2025-10-27 09:25:25', '2025-10-27 09:25:25'),
(4, 'Flamanzi', 'Flamanzi', 'Botosani', -0.00823975, 0.01132965, '2025-10-27 09:25:37', '2025-10-27 09:25:37'),
(5, 'Dorohoi', 'Dorohoi', 'Botoșani', -0.00858307, 0.00377655, '2025-10-27 13:59:04', '2025-10-27 13:59:04');

-- --------------------------------------------------------

--
-- Table structure for table `traveler_defaults`
--

CREATE TABLE `traveler_defaults` (
  `id` int(11) NOT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `route_id` int(11) DEFAULT NULL,
  `use_count` int(11) DEFAULT 0,
  `last_used_at` datetime DEFAULT NULL,
  `board_station_id` int(11) DEFAULT NULL,
  `exit_station_id` int(11) DEFAULT NULL,
  `direction` enum('tur','retur') NOT NULL DEFAULT 'tur'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `traveler_defaults`
--

INSERT INTO `traveler_defaults` (`id`, `phone`, `route_id`, `use_count`, `last_used_at`, `board_station_id`, `exit_station_id`, `direction`) VALUES
(5, '0743171315', 1, 4, '2025-10-27 15:34:00', 2, 1, 'retur'),
(3, '1234567890', 1, 8, '2025-10-28 14:20:19', 1, 3, 'tur'),
(4, '1234567890', 2, 1, '2025-10-27 14:11:03', 1, 3, 'retur'),
(6, '7894561234', 1, 1, '2025-10-27 15:39:46', 2, 1, 'retur');

-- --------------------------------------------------------

--
-- Table structure for table `trips`
--

CREATE TABLE `trips` (
  `id` int(11) NOT NULL,
  `route_id` int(11) DEFAULT NULL,
  `vehicle_id` int(11) DEFAULT NULL,
  `date` date DEFAULT NULL,
  `time` time DEFAULT NULL,
  `disabled` tinyint(1) NOT NULL DEFAULT 0,
  `route_schedule_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `trips`
--

INSERT INTO `trips` (`id`, `route_id`, `vehicle_id`, `date`, `time`, `disabled`, `route_schedule_id`) VALUES
(9092, 1, 2, '2025-10-30', '06:00:00', 0, 1),
(9093, 1, 1, '2025-10-30', '07:00:00', 0, 2),
(9095, 1, 1, '2025-10-30', '08:00:00', 0, 3),
(9096, 1, 1, '2025-10-30', '09:00:00', 0, 4),
(9097, 1, 1, '2025-10-30', '10:00:00', 0, 5),
(9098, 1, 1, '2025-10-30', '11:00:00', 0, 6),
(9099, 2, 1, '2025-10-30', '07:00:00', 0, 7),
(9100, 2, 1, '2025-10-30', '10:00:00', 0, 8),
(9101, 1, 2, '2025-10-31', '06:00:00', 0, 1),
(9102, 1, 1, '2025-10-31', '07:00:00', 0, 2),
(9103, 1, 1, '2025-10-31', '08:00:00', 0, 3),
(9104, 1, 1, '2025-10-31', '09:00:00', 0, 4),
(9105, 1, 1, '2025-10-31', '10:00:00', 0, 5),
(9106, 1, 1, '2025-10-31', '11:00:00', 0, 6),
(9107, 2, 1, '2025-10-31', '07:00:00', 0, 7),
(9108, 2, 1, '2025-10-31', '10:00:00', 0, 8),
(9109, 1, 2, '2025-11-01', '06:00:00', 0, 1),
(9110, 1, 1, '2025-11-01', '07:00:00', 0, 2),
(9111, 1, 1, '2025-11-01', '08:00:00', 0, 3),
(9112, 1, 1, '2025-11-01', '09:00:00', 0, 4),
(9113, 1, 1, '2025-11-01', '10:00:00', 0, 5),
(9114, 1, 1, '2025-11-01', '11:00:00', 0, 6),
(9115, 2, 1, '2025-11-01', '07:00:00', 0, 7),
(9116, 2, 1, '2025-11-01', '10:00:00', 0, 8),
(9117, 1, 2, '2025-11-02', '06:00:00', 0, 1),
(9118, 1, 1, '2025-11-02', '07:00:00', 0, 2),
(9119, 1, 1, '2025-11-02', '08:00:00', 0, 3),
(9120, 1, 1, '2025-11-02', '09:00:00', 0, 4),
(9121, 1, 1, '2025-11-02', '10:00:00', 0, 5),
(9122, 1, 1, '2025-11-02', '11:00:00', 0, 6),
(9123, 2, 1, '2025-11-02', '07:00:00', 0, 7),
(9124, 2, 1, '2025-11-02', '10:00:00', 0, 8),
(9125, 1, 2, '2025-11-03', '06:00:00', 0, 1),
(9126, 1, 1, '2025-11-03', '07:00:00', 0, 2),
(9127, 1, 1, '2025-11-03', '08:00:00', 0, 3),
(9128, 1, 1, '2025-11-03', '09:00:00', 0, 4),
(9129, 1, 1, '2025-11-03', '10:00:00', 0, 5),
(9130, 1, 1, '2025-11-03', '11:00:00', 0, 6),
(9131, 2, 1, '2025-11-03', '07:00:00', 0, 7),
(9132, 2, 1, '2025-11-03', '10:00:00', 0, 8),
(9133, 1, 2, '2025-11-04', '06:00:00', 0, 1),
(9134, 1, 1, '2025-11-04', '07:00:00', 0, 2),
(9135, 1, 1, '2025-11-04', '08:00:00', 0, 3),
(9136, 1, 1, '2025-11-04', '09:00:00', 0, 4),
(9137, 1, 1, '2025-11-04', '10:00:00', 0, 5),
(9138, 1, 1, '2025-11-04', '11:00:00', 0, 6),
(9139, 2, 1, '2025-11-04', '07:00:00', 0, 7),
(9140, 2, 1, '2025-11-04', '10:00:00', 0, 8),
(9141, 1, 2, '2025-11-05', '06:00:00', 0, 1),
(9142, 1, 1, '2025-11-05', '07:00:00', 0, 2),
(9143, 1, 1, '2025-11-05', '08:00:00', 0, 3),
(9144, 1, 1, '2025-11-05', '09:00:00', 0, 4),
(9145, 1, 1, '2025-11-05', '10:00:00', 0, 5),
(9146, 1, 1, '2025-11-05', '11:00:00', 0, 6),
(9147, 2, 1, '2025-11-05', '07:00:00', 0, 7),
(9148, 2, 1, '2025-11-05', '10:00:00', 0, 8);

--
-- Triggers `trips`
--
DELIMITER $$
CREATE TRIGGER `trg_trips_ai_snapshot` AFTER INSERT ON `trips` FOR EACH ROW BEGIN
  CALL sp_fill_trip_stations(NEW.id);
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `trip_stations`
--

CREATE TABLE `trip_stations` (
  `trip_id` int(11) NOT NULL,
  `station_id` int(11) NOT NULL,
  `sequence` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `trip_stations`
--

INSERT INTO `trip_stations` (`trip_id`, `station_id`, `sequence`) VALUES
(9092, 1, 1),
(9092, 4, 2),
(9092, 3, 3),
(9092, 2, 4),
(9093, 2, 1),
(9093, 3, 2),
(9093, 4, 3),
(9093, 1, 4),
(9095, 1, 1),
(9095, 4, 2),
(9095, 3, 3),
(9095, 2, 4),
(9096, 2, 1),
(9096, 3, 2),
(9096, 4, 3),
(9096, 1, 4),
(9097, 1, 1),
(9097, 4, 2),
(9097, 3, 3),
(9097, 2, 4),
(9098, 1, 1),
(9098, 4, 2),
(9098, 3, 3),
(9098, 2, 4),
(9099, 5, 1),
(9099, 1, 2),
(9099, 4, 3),
(9099, 3, 4),
(9099, 2, 5),
(9100, 2, 1),
(9100, 3, 2),
(9100, 4, 3),
(9100, 1, 4),
(9100, 5, 5),
(9101, 1, 1),
(9101, 4, 2),
(9101, 3, 3),
(9101, 2, 4),
(9102, 2, 1),
(9102, 3, 2),
(9102, 4, 3),
(9102, 1, 4),
(9103, 1, 1),
(9103, 4, 2),
(9103, 3, 3),
(9103, 2, 4),
(9104, 2, 1),
(9104, 3, 2),
(9104, 4, 3),
(9104, 1, 4),
(9105, 1, 1),
(9105, 4, 2),
(9105, 3, 3),
(9105, 2, 4),
(9106, 1, 1),
(9106, 4, 2),
(9106, 3, 3),
(9106, 2, 4),
(9107, 5, 1),
(9107, 1, 2),
(9107, 4, 3),
(9107, 3, 4),
(9107, 2, 5),
(9108, 2, 1),
(9108, 3, 2),
(9108, 4, 3),
(9108, 1, 4),
(9108, 5, 5),
(9109, 1, 1),
(9109, 4, 2),
(9109, 3, 3),
(9109, 2, 4),
(9110, 2, 1),
(9110, 3, 2),
(9110, 4, 3),
(9110, 1, 4),
(9111, 1, 1),
(9111, 4, 2),
(9111, 3, 3),
(9111, 2, 4),
(9112, 2, 1),
(9112, 3, 2),
(9112, 4, 3),
(9112, 1, 4),
(9113, 1, 1),
(9113, 4, 2),
(9113, 3, 3),
(9113, 2, 4),
(9114, 1, 1),
(9114, 4, 2),
(9114, 3, 3),
(9114, 2, 4),
(9115, 5, 1),
(9115, 1, 2),
(9115, 4, 3),
(9115, 3, 4),
(9115, 2, 5),
(9116, 2, 1),
(9116, 3, 2),
(9116, 4, 3),
(9116, 1, 4),
(9116, 5, 5),
(9117, 1, 1),
(9117, 4, 2),
(9117, 3, 3),
(9117, 2, 4),
(9118, 2, 1),
(9118, 3, 2),
(9118, 4, 3),
(9118, 1, 4),
(9119, 1, 1),
(9119, 4, 2),
(9119, 3, 3),
(9119, 2, 4),
(9120, 2, 1),
(9120, 3, 2),
(9120, 4, 3),
(9120, 1, 4),
(9121, 1, 1),
(9121, 4, 2),
(9121, 3, 3),
(9121, 2, 4),
(9122, 1, 1),
(9122, 4, 2),
(9122, 3, 3),
(9122, 2, 4),
(9123, 5, 1),
(9123, 1, 2),
(9123, 4, 3),
(9123, 3, 4),
(9123, 2, 5),
(9124, 2, 1),
(9124, 3, 2),
(9124, 4, 3),
(9124, 1, 4),
(9124, 5, 5),
(9125, 1, 1),
(9125, 4, 2),
(9125, 3, 3),
(9125, 2, 4),
(9126, 2, 1),
(9126, 3, 2),
(9126, 4, 3),
(9126, 1, 4),
(9127, 1, 1),
(9127, 4, 2),
(9127, 3, 3),
(9127, 2, 4),
(9128, 2, 1),
(9128, 3, 2),
(9128, 4, 3),
(9128, 1, 4),
(9129, 1, 1),
(9129, 4, 2),
(9129, 3, 3),
(9129, 2, 4),
(9130, 1, 1),
(9130, 4, 2),
(9130, 3, 3),
(9130, 2, 4),
(9131, 5, 1),
(9131, 1, 2),
(9131, 4, 3),
(9131, 3, 4),
(9131, 2, 5),
(9132, 2, 1),
(9132, 3, 2),
(9132, 4, 3),
(9132, 1, 4),
(9132, 5, 5),
(9133, 1, 1),
(9133, 4, 2),
(9133, 3, 3),
(9133, 2, 4),
(9134, 2, 1),
(9134, 3, 2),
(9134, 4, 3),
(9134, 1, 4),
(9135, 1, 1),
(9135, 4, 2),
(9135, 3, 3),
(9135, 2, 4),
(9136, 2, 1),
(9136, 3, 2),
(9136, 4, 3),
(9136, 1, 4),
(9137, 1, 1),
(9137, 4, 2),
(9137, 3, 3),
(9137, 2, 4),
(9138, 1, 1),
(9138, 4, 2),
(9138, 3, 3),
(9138, 2, 4),
(9139, 5, 1),
(9139, 1, 2),
(9139, 4, 3),
(9139, 3, 4),
(9139, 2, 5),
(9140, 2, 1),
(9140, 3, 2),
(9140, 4, 3),
(9140, 1, 4),
(9140, 5, 5),
(9141, 1, 1),
(9141, 4, 2),
(9141, 3, 3),
(9141, 2, 4),
(9142, 2, 1),
(9142, 3, 2),
(9142, 4, 3),
(9142, 1, 4),
(9143, 1, 1),
(9143, 4, 2),
(9143, 3, 3),
(9143, 2, 4),
(9144, 2, 1),
(9144, 3, 2),
(9144, 4, 3),
(9144, 1, 4),
(9145, 1, 1),
(9145, 4, 2),
(9145, 3, 3),
(9145, 2, 4),
(9146, 1, 1),
(9146, 4, 2),
(9146, 3, 3),
(9146, 2, 4),
(9147, 5, 1),
(9147, 1, 2),
(9147, 4, 3),
(9147, 3, 4),
(9147, 2, 5),
(9148, 2, 1),
(9148, 3, 2),
(9148, 4, 3),
(9148, 1, 4),
(9148, 5, 5);

-- --------------------------------------------------------

--
-- Table structure for table `trip_vehicles`
--

CREATE TABLE `trip_vehicles` (
  `id` int(11) NOT NULL,
  `trip_id` int(11) DEFAULT NULL,
  `vehicle_id` int(11) DEFAULT NULL,
  `is_primary` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `trip_vehicles`
--

INSERT INTO `trip_vehicles` (`id`, `trip_id`, `vehicle_id`, `is_primary`) VALUES
(8871, 8867, 4, 1),
(8873, 8868, 2, 1),
(8875, 8870, 1, 1),
(8877, 8872, 1, 1),
(8879, 8874, 1, 1),
(8881, 8876, 1, 1),
(8883, 8878, 1, 1),
(8885, 8880, 1, 1),
(8887, 8882, 1, 1),
(8889, 8884, 2, 1),
(8891, 8886, 1, 1),
(8893, 8888, 1, 1),
(8895, 8890, 1, 1),
(8897, 8892, 1, 1),
(8899, 8894, 1, 1),
(8901, 8896, 1, 1),
(8903, 8898, 1, 1),
(8905, 8900, 2, 1),
(8907, 8902, 1, 1),
(8909, 8904, 1, 1),
(8911, 8906, 1, 1),
(8913, 8908, 1, 1),
(8915, 8910, 1, 1),
(8917, 8912, 1, 1),
(8919, 8914, 1, 1),
(8921, 8916, 2, 1),
(8923, 8918, 1, 1),
(8925, 8920, 1, 1),
(8927, 8922, 1, 1),
(8929, 8924, 1, 1),
(8931, 8926, 1, 1),
(8933, 8928, 1, 1),
(8935, 8930, 1, 1),
(8937, 8932, 2, 1),
(8939, 8934, 1, 1),
(8941, 8936, 1, 1),
(8943, 8938, 1, 1),
(8945, 8940, 1, 1),
(8947, 8942, 1, 1),
(8949, 8944, 1, 1),
(8951, 8946, 1, 1),
(8953, 8948, 2, 1),
(8955, 8950, 1, 1),
(8957, 8952, 1, 1),
(8959, 8954, 1, 1),
(8961, 8956, 1, 1),
(8963, 8958, 1, 1),
(8965, 8960, 1, 1),
(8967, 8962, 1, 1),
(8969, 8964, 2, 1),
(8971, 8966, 1, 1),
(8973, 8968, 1, 1),
(8975, 8970, 1, 1),
(8977, 8972, 1, 1),
(8979, 8974, 1, 1),
(8981, 8976, 1, 1),
(8983, 8978, 1, 1),
(9097, 9092, 2, 1),
(9098, 9093, 1, 1),
(9099, 9095, 1, 1),
(9100, 9096, 1, 1),
(9101, 9097, 1, 1),
(9102, 9098, 1, 1),
(9103, 9099, 1, 1),
(9104, 9100, 1, 1),
(9105, 9101, 2, 1),
(9106, 9102, 1, 1),
(9107, 9103, 1, 1),
(9108, 9104, 1, 1),
(9109, 9105, 1, 1),
(9110, 9106, 1, 1),
(9111, 9107, 1, 1),
(9112, 9108, 1, 1),
(9113, 9109, 2, 1),
(9114, 9110, 1, 1),
(9115, 9111, 1, 1),
(9116, 9112, 1, 1),
(9117, 9113, 1, 1),
(9118, 9114, 1, 1),
(9119, 9115, 1, 1),
(9120, 9116, 1, 1),
(9121, 9117, 2, 1),
(9122, 9118, 1, 1),
(9123, 9119, 1, 1),
(9124, 9120, 1, 1),
(9125, 9121, 1, 1),
(9126, 9122, 1, 1),
(9127, 9123, 1, 1),
(9128, 9124, 1, 1),
(9129, 9125, 2, 1),
(9130, 9126, 1, 1),
(9131, 9127, 1, 1),
(9132, 9128, 1, 1),
(9133, 9129, 1, 1),
(9134, 9130, 1, 1),
(9135, 9131, 1, 1),
(9136, 9132, 1, 1),
(9137, 9133, 2, 1),
(9138, 9134, 1, 1),
(9139, 9135, 1, 1),
(9140, 9136, 1, 1),
(9141, 9137, 1, 1),
(9142, 9138, 1, 1),
(9143, 9139, 1, 1),
(9144, 9140, 1, 1),
(9145, 9141, 2, 1),
(9146, 9142, 1, 1),
(9147, 9143, 1, 1),
(9148, 9144, 1, 1),
(9149, 9145, 1, 1),
(9150, 9146, 1, 1),
(9151, 9147, 1, 1),
(9152, 9148, 1, 1);

-- --------------------------------------------------------

--
-- Table structure for table `trip_vehicle_employees`
--

CREATE TABLE `trip_vehicle_employees` (
  `id` int(11) NOT NULL,
  `trip_vehicle_id` int(11) DEFAULT NULL,
  `employee_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user_preferences`
--

CREATE TABLE `user_preferences` (
  `user_id` bigint(20) NOT NULL,
  `prefs_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT json_object() CHECK (json_valid(`prefs_json`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user_route_order`
--

CREATE TABLE `user_route_order` (
  `id` bigint(20) NOT NULL,
  `user_id` bigint(20) NOT NULL,
  `route_id` bigint(20) NOT NULL,
  `position_idx` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vehicles`
--

CREATE TABLE `vehicles` (
  `id` int(11) NOT NULL,
  `name` text NOT NULL,
  `seat_count` int(11) DEFAULT NULL,
  `type` varchar(20) DEFAULT NULL,
  `plate_number` varchar(20) DEFAULT NULL,
  `operator_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `vehicles`
--

INSERT INTO `vehicles` (`id`, `name`, `seat_count`, `type`, `plate_number`, `operator_id`) VALUES
(1, 'Microbuz', 20, 'microbuz', 'BT22DMS', 2),
(2, 'Microbuz', 20, 'microbuz', 'BT01PRI', 1),
(3, 'Tourisomo', 52, 'autocar', 'BT21DMS', 2),
(4, 'TEST', 50, 'autocar', 'testPRI', 1);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `agencies`
--
ALTER TABLE `agencies`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `agent_chat_messages`
--
ALTER TABLE `agent_chat_messages`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `app_settings`
--
ALTER TABLE `app_settings`
  ADD PRIMARY KEY (`setting_key`);

--
-- Indexes for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_audit_created_at` (`created_at`),
  ADD KEY `idx_audit_action` (`action`),
  ADD KEY `idx_audit_entity_id` (`entity`,`entity_id`),
  ADD KEY `idx_audit_related_id` (`related_entity`,`related_id`);

--
-- Indexes for table `blacklist`
--
ALTER TABLE `blacklist`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `cash_handovers`
--
ALTER TABLE `cash_handovers`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `discount_types`
--
ALTER TABLE `discount_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`);

--
-- Indexes for table `employees`
--
ALTER TABLE `employees`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_employees_role` (`role`);

--
-- Indexes for table `idempotency_keys`
--
ALTER TABLE `idempotency_keys`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_user_key` (`user_id`,`idem_key`);

--
-- Indexes for table `invitations`
--
ALTER TABLE `invitations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token` (`token`),
  ADD KEY `fk_inv_operator` (`operator_id`);

--
-- Indexes for table `no_shows`
--
ALTER TABLE `no_shows`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `operators`
--
ALTER TABLE `operators`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `payments`
--
ALTER TABLE `payments`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `people`
--
ALTER TABLE `people`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ux_people_phone_active` (`phone`,`is_active`),
  ADD KEY `ix_people_owner_changed_by` (`owner_changed_by`),
  ADD KEY `ix_people_owner_changed_at` (`owner_changed_at`);

--
-- Indexes for table `price_lists`
--
ALTER TABLE `price_lists`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `price_list_items`
--
ALTER TABLE `price_list_items`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_price_list_items_unique` (`price_list_id`,`from_station_id`,`to_station_id`);

--
-- Indexes for table `pricing_categories`
--
ALTER TABLE `pricing_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `promo_codes`
--
ALTER TABLE `promo_codes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`);

--
-- Indexes for table `promo_code_hours`
--
ALTER TABLE `promo_code_hours`
  ADD PRIMARY KEY (`promo_code_id`,`start_time`,`end_time`);

--
-- Indexes for table `promo_code_routes`
--
ALTER TABLE `promo_code_routes`
  ADD PRIMARY KEY (`promo_code_id`,`route_id`),
  ADD KEY `route_id` (`route_id`);

--
-- Indexes for table `promo_code_schedules`
--
ALTER TABLE `promo_code_schedules`
  ADD PRIMARY KEY (`promo_code_id`,`route_schedule_id`),
  ADD KEY `route_schedule_id` (`route_schedule_id`);

--
-- Indexes for table `promo_code_usages`
--
ALTER TABLE `promo_code_usages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `promo_code_id` (`promo_code_id`);

--
-- Indexes for table `promo_code_weekdays`
--
ALTER TABLE `promo_code_weekdays`
  ADD PRIMARY KEY (`promo_code_id`,`weekday`);

--
-- Indexes for table `reservations`
--
ALTER TABLE `reservations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ix_res_trip_seat_status` (`trip_id`,`seat_id`,`status`),
  ADD KEY `ix_res_person_time` (`person_id`,`reservation_time`);

--
-- Indexes for table `reservations_backup`
--
ALTER TABLE `reservations_backup`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `reservation_discounts`
--
ALTER TABLE `reservation_discounts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_resdisc_promo` (`promo_code_id`);

--
-- Indexes for table `reservation_events`
--
ALTER TABLE `reservation_events`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_reservation` (`reservation_id`);

--
-- Indexes for table `reservation_intents`
--
ALTER TABLE `reservation_intents`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_trip_seat` (`trip_id`,`seat_id`);

--
-- Indexes for table `reservation_pricing`
--
ALTER TABLE `reservation_pricing`
  ADD PRIMARY KEY (`reservation_id`);

--
-- Indexes for table `routes`
--
ALTER TABLE `routes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `route_schedules`
--
ALTER TABLE `route_schedules`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_route_time_dir_op` (`route_id`,`departure`,`direction`,`operator_id`);

--
-- Indexes for table `route_schedule_discounts`
--
ALTER TABLE `route_schedule_discounts`
  ADD PRIMARY KEY (`discount_type_id`,`route_schedule_id`);

--
-- Indexes for table `route_schedule_pricing_categories`
--
ALTER TABLE `route_schedule_pricing_categories`
  ADD PRIMARY KEY (`route_schedule_id`,`pricing_category_id`),
  ADD KEY `route_schedule_pricing_categories_category_id_idx` (`pricing_category_id`);

--
-- Indexes for table `route_stations`
--
ALTER TABLE `route_stations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_route_station` (`route_id`,`station_id`),
  ADD KEY `idx_route_seq` (`route_id`,`sequence`),
  ADD KEY `ix_rs_route_station` (`route_id`,`station_id`),
  ADD KEY `ix_rs_route_sequence` (`route_id`,`sequence`);

--
-- Indexes for table `schedule_exceptions`
--
ALTER TABLE `schedule_exceptions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_schedule` (`schedule_id`),
  ADD KEY `idx_exception_date` (`exception_date`),
  ADD KEY `idx_weekday` (`weekday`),
  ADD KEY `idx_sched_date_week` (`schedule_id`,`exception_date`,`weekday`);

--
-- Indexes for table `seats`
--
ALTER TABLE `seats`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_vehicle_grid` (`vehicle_id`,`row`,`seat_col`),
  ADD UNIQUE KEY `uq_vehicle_label` (`vehicle_id`,`label`) USING HASH,
  ADD KEY `idx_pair` (`vehicle_id`,`pair_id`);

--
-- Indexes for table `seat_locks`
--
ALTER TABLE `seat_locks`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_hold_token` (`hold_token`),
  ADD KEY `idx_trip_seat` (`trip_id`,`seat_id`),
  ADD KEY `idx_expires` (`expires_at`);

--
-- Indexes for table `sessions`
--
ALTER TABLE `sessions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `token_hash` (`token_hash`),
  ADD KEY `idx_sessions_emp` (`employee_id`),
  ADD KEY `idx_sessions_exp` (`expires_at`);

--
-- Indexes for table `stations`
--
ALTER TABLE `stations`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `traveler_defaults`
--
ALTER TABLE `traveler_defaults`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_phone_route_dir` (`phone`,`route_id`,`direction`),
  ADD KEY `idx_phone_stations` (`phone`,`board_station_id`,`exit_station_id`),
  ADD KEY `ix_td_read` (`phone`,`route_id`,`direction`,`use_count`,`last_used_at`,`board_station_id`,`exit_station_id`);

--
-- Indexes for table `trips`
--
ALTER TABLE `trips`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_trips_route_date_time_vehicle` (`route_id`,`date`,`time`,`vehicle_id`);

--
-- Indexes for table `trip_stations`
--
ALTER TABLE `trip_stations`
  ADD PRIMARY KEY (`trip_id`,`station_id`),
  ADD UNIQUE KEY `uq_trip_seq` (`trip_id`,`sequence`),
  ADD KEY `fk_ts_station` (`station_id`);

--
-- Indexes for table `trip_vehicles`
--
ALTER TABLE `trip_vehicles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_tv_trip_vehicle` (`trip_id`,`vehicle_id`),
  ADD KEY `idx_tv_trip` (`trip_id`),
  ADD KEY `idx_tv_vehicle` (`vehicle_id`);

--
-- Indexes for table `trip_vehicle_employees`
--
ALTER TABLE `trip_vehicle_employees`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_tve_trip_employee` (`trip_vehicle_id`,`employee_id`),
  ADD KEY `idx_tve_trip_vehicle_id` (`trip_vehicle_id`),
  ADD KEY `idx_tve_employee_id` (`employee_id`);

--
-- Indexes for table `user_preferences`
--
ALTER TABLE `user_preferences`
  ADD PRIMARY KEY (`user_id`);

--
-- Indexes for table `user_route_order`
--
ALTER TABLE `user_route_order`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_user_route` (`user_id`,`route_id`),
  ADD KEY `idx_user_pos` (`user_id`,`position_idx`);

--
-- Indexes for table `vehicles`
--
ALTER TABLE `vehicles`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `agencies`
--
ALTER TABLE `agencies`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `agent_chat_messages`
--
ALTER TABLE `agent_chat_messages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `audit_logs`
--
ALTER TABLE `audit_logs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=85;

--
-- AUTO_INCREMENT for table `blacklist`
--
ALTER TABLE `blacklist`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `cash_handovers`
--
ALTER TABLE `cash_handovers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `discount_types`
--
ALTER TABLE `discount_types`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `employees`
--
ALTER TABLE `employees`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `idempotency_keys`
--
ALTER TABLE `idempotency_keys`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=26;

--
-- AUTO_INCREMENT for table `invitations`
--
ALTER TABLE `invitations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `no_shows`
--
ALTER TABLE `no_shows`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `operators`
--
ALTER TABLE `operators`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `payments`
--
ALTER TABLE `payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people`
--
ALTER TABLE `people`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT for table `price_lists`
--
ALTER TABLE `price_lists`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `price_list_items`
--
ALTER TABLE `price_list_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=273;

--
-- AUTO_INCREMENT for table `pricing_categories`
--
ALTER TABLE `pricing_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `promo_codes`
--
ALTER TABLE `promo_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `promo_code_usages`
--
ALTER TABLE `promo_code_usages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `reservations`
--
ALTER TABLE `reservations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=72;

--
-- AUTO_INCREMENT for table `reservations_backup`
--
ALTER TABLE `reservations_backup`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `reservation_discounts`
--
ALTER TABLE `reservation_discounts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `reservation_events`
--
ALTER TABLE `reservation_events`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `reservation_intents`
--
ALTER TABLE `reservation_intents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=534;

--
-- AUTO_INCREMENT for table `routes`
--
ALTER TABLE `routes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `route_schedules`
--
ALTER TABLE `route_schedules`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `route_stations`
--
ALTER TABLE `route_stations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `schedule_exceptions`
--
ALTER TABLE `schedule_exceptions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `seats`
--
ALTER TABLE `seats`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=151;

--
-- AUTO_INCREMENT for table `seat_locks`
--
ALTER TABLE `seat_locks`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=470;

--
-- AUTO_INCREMENT for table `sessions`
--
ALTER TABLE `sessions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=25;

--
-- AUTO_INCREMENT for table `stations`
--
ALTER TABLE `stations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `traveler_defaults`
--
ALTER TABLE `traveler_defaults`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `trips`
--
ALTER TABLE `trips`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9149;

--
-- AUTO_INCREMENT for table `trip_vehicles`
--
ALTER TABLE `trip_vehicles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9153;

--
-- AUTO_INCREMENT for table `trip_vehicle_employees`
--
ALTER TABLE `trip_vehicle_employees`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `user_route_order`
--
ALTER TABLE `user_route_order`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vehicles`
--
ALTER TABLE `vehicles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `invitations`
--
ALTER TABLE `invitations`
  ADD CONSTRAINT `fk_inv_operator` FOREIGN KEY (`operator_id`) REFERENCES `operators` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `promo_code_hours`
--
ALTER TABLE `promo_code_hours`
  ADD CONSTRAINT `fk_promo_hours_code` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `promo_code_routes`
--
ALTER TABLE `promo_code_routes`
  ADD CONSTRAINT `fk_promo_routes_code` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `promo_code_schedules`
--
ALTER TABLE `promo_code_schedules`
  ADD CONSTRAINT `fk_promo_sched_code` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `promo_code_usages`
--
ALTER TABLE `promo_code_usages`
  ADD CONSTRAINT `fk_promo_usages_code` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `promo_code_weekdays`
--
ALTER TABLE `promo_code_weekdays`
  ADD CONSTRAINT `fk_promo_weekdays_code` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `reservation_discounts`
--
ALTER TABLE `reservation_discounts`
  ADD CONSTRAINT `fk_resdisc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`);

--
-- Constraints for table `reservation_events`
--
ALTER TABLE `reservation_events`
  ADD CONSTRAINT `fk_reservation_events_res` FOREIGN KEY (`reservation_id`) REFERENCES `reservations` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `route_schedule_pricing_categories`
--
ALTER TABLE `route_schedule_pricing_categories`
  ADD CONSTRAINT `fk_rspc_category` FOREIGN KEY (`pricing_category_id`) REFERENCES `pricing_categories` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_rspc_schedule` FOREIGN KEY (`route_schedule_id`) REFERENCES `route_schedules` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `schedule_exceptions`
--
ALTER TABLE `schedule_exceptions`
  ADD CONSTRAINT `fk_se_schedule` FOREIGN KEY (`schedule_id`) REFERENCES `route_schedules` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `sessions`
--
ALTER TABLE `sessions`
  ADD CONSTRAINT `fk_sess_emp` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `trip_stations`
--
ALTER TABLE `trip_stations`
  ADD CONSTRAINT `fk_ts_station` FOREIGN KEY (`station_id`) REFERENCES `stations` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ts_trip` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

DELIMITER $$
--
-- Events
--
CREATE DEFINER=`priscomr_rezervariuser`@`%` EVENT `ev_cleanup_reservation_intents` ON SCHEDULE EVERY 1 MINUTE STARTS '2025-10-27 12:43:14' ON COMPLETION NOT PRESERVE ENABLE DO DELETE FROM reservation_intents WHERE expires_at <= NOW()$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
