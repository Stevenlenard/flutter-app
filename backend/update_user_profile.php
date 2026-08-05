<?php
header("Content-Type: application/json");
require_once 'db_config.php';

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->user_id) && !empty($data->role) && !empty($data->name)) {
    try {
        $table = ($data->role === 'resident') ? "residents" : "users";
        $id_col = ($data->role === 'resident') ? "resident_id" : "user_id";

        $updateFields = [];
        $params = [];

        $updateFields[] = "name = ?";
        $params[] = $data->name;

        if (isset($data->phone)) {
            $updateFields[] = "phone = ?";
            $params[] = $data->phone;
        }

        if (isset($data->email)) {
            $updateFields[] = "email = ?";
            $params[] = $data->email;
        }

        if ($data->role !== 'resident') {
            if (isset($data->preferred_truck)) {
                $updateFields[] = "preferred_truck = ?";
                $params[] = $data->preferred_truck;
            }
            if (isset($data->license_number)) {
                $updateFields[] = "license_number = ?";
                $params[] = $data->license_number;
            }
        } else {
            if (isset($data->complete_address)) {
                $updateFields[] = "complete_address = ?";
                $params[] = $data->complete_address;
            }
        }

        $sql = "UPDATE $table SET " . implode(", ", $updateFields) . " WHERE $id_col = ?";
        $params[] = $data->user_id;

        $stmt = $conn->prepare($sql);
        $stmt->execute($params);

        // Fetch updated user data to return
        $query = "SELECT * FROM $table WHERE $id_col = ?";
        $stmt = $conn->prepare($query);
        $stmt->execute([$data->user_id]);
        $updatedUser = $stmt->fetch(PDO::FETCH_ASSOC);

        echo json_encode([
            "success" => true,
            "message" => "Profile updated successfully",
            "user" => $updatedUser
        ]);
    } catch (PDOException $e) {
        echo json_encode(["success" => false, "message" => "Database Error: " . $e->getMessage()]);
    }
} else {
    echo json_encode(["success" => false, "message" => "Required data missing"]);
}
?>
