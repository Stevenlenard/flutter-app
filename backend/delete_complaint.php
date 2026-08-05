<?php
header("Content-Type: application/json");
require_once 'db_config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $json = json_decode(file_get_contents('php://input'), true);
    $complaint_id = $_POST['complaint_id'] ?? $json['complaint_id'] ?? $_REQUEST['complaint_id'] ?? null;
    $action = $_POST['action'] ?? $json['action'] ?? $_REQUEST['action'] ?? 'delete';

    if ($complaint_id) {
        try {
            // First, ensure the deletion column exists
            $conn->exec("ALTER TABLE complaints ADD COLUMN IF NOT EXISTS deleted_by_resident TINYINT(1) DEFAULT 0");

            $columns = $conn->query("DESCRIBE complaints")->fetchAll(PDO::FETCH_COLUMN);
            $id_col = in_array('complaint_id', $columns) ? 'complaint_id' : 'id';

            if ($action === 'undo') {
                $query = "DELETE FROM complaints WHERE $id_col = ?";
                $stmt = $conn->prepare($query);
                $stmt->execute([$complaint_id]);
                $msg = "Hard delete completed";
            } else {
                $query = "UPDATE complaints SET deleted_by_resident = 1 WHERE $id_col = ?";
                $stmt = $conn->prepare($query);
                $stmt->execute([$complaint_id]);
                $msg = "Soft delete completed";
            }

            echo json_encode(["success" => true, "message" => $msg]);
        } catch (PDOException $e) {
            echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
        }
    } else {
        echo json_encode(["success" => false, "message" => "Missing complaint_id"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
}
?>
